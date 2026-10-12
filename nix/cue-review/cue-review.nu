# cue-review: deterministic multi-agent code review driving cue-agent.
#
# Spec: palekiwi/palekiwi/cue-review-script/spec/index.md
# Interfaces: palekiwi/palekiwi/cue-review-script/note/concrete-interfaces.md
#
# Exit codes: 0 all artifacts produced (or empty diff), 1 missing artifacts
# or a phase produced none, 2 validation error before any agent ran,
# 130 interrupted (mapped by the packaged bash wrapper, since nu aborts on
# SIGINT before it can report). Progress on stderr, summary on stdout.

const PHASES = [reviewers merge verifiers]
const ENTRY_FIELDS = [name agent prompt model thinking system_prompt]
const MAX_ENTRIES = 4

def log [msg: string] { print -e $"cue-review: ($msg)" }

def die [msg: string, code: int = 2] {
  log $"error: ($msg)"
  exit $code
}

def main [] {
  print -e "usage: cue-review run --manifest <path> --context <slug> --base <ref> [--head <ref>] [-C <dir>]"
  exit 2
}

# Resolve a string-or-{file} value relative to the manifest directory.
def resolve-text [value: any, dir: path, what: string] {
  match ($value | describe | str replace -r '<.*' '') {
    "string" => $value
    "record" => {
      if ($value | columns) != [file] { die $"($what): expected a string or { \"file\": ... }" }
      let p = ($dir | path join $value.file)
      if not ($p | path exists) { die $"($what): file not found: ($p)" }
      open --raw $p
    }
    _ => { die $"($what): expected a string or { \"file\": ... }" }
  }
}

# Validate the manifest and return { reviewers: [...], merge: [...], verifiers: [...] }
# with prompts resolved to strings.
def load-manifest [file: path] {
  if not ($file | path exists) { die $"manifest not found: ($file)" }
  let raw = try { open --raw $file | from json } catch { die $"manifest is not valid JSON: ($file)" }
  if ($raw | describe | str starts-with "record") == false { die "manifest: root must be an object" }
  let unknown = ($raw | columns | where {|k| $k not-in $PHASES })
  if ($unknown | is-not-empty) { die $"manifest: unknown keys: ($unknown | str join ', ')" }
  let dir = ($file | path dirname)

  $PHASES | each {|phase|
    let entries = ($raw | get -o $phase | default [])
    if ($entries | describe | str starts-with "list") == false and ($entries | describe | str starts-with "table") == false {
      die $"manifest: ($phase) must be a list"
    }
    let n = ($entries | length)
    if $phase != "merge" and $n == 0 { die $"manifest: ($phase) needs at least one entry" }
    if $n > $MAX_ENTRIES { die $"manifest: ($phase) has ($n) entries, max ($MAX_ENTRIES)" }

    let resolved = ($entries | enumerate | each {|it|
      let e = $it.item
      let at = $"($phase)[($it.index)]"
      if ($e | describe | str starts-with "record") == false { die $"manifest: ($at) must be an object" }
      let bad = ($e | columns | where {|k| $k not-in $ENTRY_FIELDS })
      if ($bad | is-not-empty) { die $"manifest: ($at): unknown keys: ($bad | str join ', ')" }
      for k in [name agent prompt] {
        if ($e | get -o $k) == null { die $"manifest: ($at): missing ($k)" }
      }
      if ($e.name !~ '^[a-z0-9-]+$') { die $"manifest: ($at): name must match [a-z0-9-]+" }
      {
        name: $e.name
        agent: $e.agent
        prompt: (resolve-text $e.prompt $dir $"($at).prompt")
        model: ($e | get -o model)
        thinking: ($e | get -o thinking)
        system_prompt: (if ($e | get -o system_prompt) == null { null } else {
          resolve-text $e.system_prompt $dir $"($at).system_prompt"
        })
      }
    })
    let names = ($resolved | get -o name | default [])
    if ($names | uniq | length) != ($names | length) { die $"manifest: ($phase): duplicate names" }
    { phase: $phase, entries: $resolved }
  } | reduce -f {} {|it, acc| $acc | insert $it.phase $it.entries }
}

def rev-parse [dir: path, ref: string] {
  let r = (do { ^git -C $dir rev-parse --verify --quiet $"($ref)^{commit}" } | complete)
  if $r.exit_code != 0 { die $"cannot resolve ref: ($ref)" }
  $r.stdout | str trim
}

def input-block [ctx: record, phase: string, name: string, inputs: list<string>] {
  let input_lines = if ($inputs | is-empty) { ["inputs: []"] } else {
    ["inputs:"] ++ ($inputs | each {|p| $"  - ($p)" })
  }
  [
    "<review-run>"
    $"phase: ($phase)"
    $"name: ($name)"
    $"context: ($ctx.slug)"
    $"run_id: ($ctx.run_id)"
    $"base: ($ctx.base)"
    $"head: ($ctx.head)"
    $"diff: ($ctx.diff)"
    ...$input_lines
    "output:"
    "  tool: cue-review"
    $"  context: ($ctx.slug)"
    $"  filename: ($ctx.run_id)/($phase)-($name).json"
    "</review-run>"
  ] | str join "\n"
}

def artifact-path [ctx: record, phase: string, name: string] {
  [$ctx.store $ctx.address review $ctx.run_id $"($phase)-($name).json"] | path join
}

# Run one phase through cue-agent. Returns { produced: [paths], missing: int, interrupted: bool }.
def run-phase [ctx: record, phase: string, entries: list, inputs: list<string>] {
  let tasks = ($entries | each {|e|
    let prompt = $"($e.prompt | str trim --right)\n\n(input-block $ctx $phase $e.name $inputs)\n"
    mut t = {
      agent: $e.agent
      prompt: $prompt
      label: $"($phase)-($e.name)"
    }
    for k in [model thinking system_prompt] {
      let v = ($e | get $k)
      if $v != null { $t = ($t | insert $k $v) }
    }
    $t
  })
  let spec = {
    label: $"review-($ctx.run_id)-($phase)"
    defaults: {
      cwd: $ctx.repo
      worktree: { base: $ctx.head, ephemeral: true }
      context: $ctx.address
      env: { CUE_CONTEXT: $ctx.slug }
    }
    tasks: $tasks
  }
  let spec_file = (mktemp -t cue-review-spec.XXXXXX.json)
  let receipt_file = (mktemp -t cue-review-receipt.XXXXXX.json)
  $spec | to json | save -f $spec_file

  log $"phase ($phase): starting ($entries | length) agent\(s\): ($entries | get name | str join ', ')"
  let start = (date now)
  # stdout (receipt) to a file; cue-agent stderr passes through.
  let code = try {
    ^cue-agent run --json --spec $spec_file o> $receipt_file
    0
  } catch {|err| $env.LAST_EXIT_CODE? | default 1 }
  rm -f $spec_file

  let receipt = try { open --raw $receipt_file | from json } catch { null }
  rm -f $receipt_file
  if $receipt == null {
    if $code == 2 { die $"phase ($phase): cue-agent rejected the run specification" }
    # No receipt: most likely interrupted before cue-agent finished.
    return { produced: [], missing: ($entries | length), interrupted: true }
  }

  let runs = $receipt.runs
  let results = ($entries | enumerate | each {|it|
    let run = ($runs | get -o $it.index)
    let path = (artifact-path $ctx $phase $it.item.name)
    let ok = ($path | path exists)
    let outcome = ($run | get -o outcome | default "unknown")
    let secs = (($run | get -o duration_ms | default 0) / 1000 | math round)
    let cost = ($run | get -o cost_usd | default 0 | math round -p 3)
    let status = if $ok { "ok" } else { "MISSING artifact" }
    mut line = $"  ($phase)-($it.item.name): ($outcome), ($secs)s, $($cost), ($status)"
    let err = ($run | get -o error)
    if (not $ok) and $err != null { $line = $"($line) -- ($err)" }
    log $line
    for c in ($run | get -o cleanup_errors | default []) { log $"  cleanup: ($c)" }
    { ok: $ok, path: $path, outcome: $outcome }
  })
  let produced = ($results | where ok | get path)
  let interrupted = ($results | any {|r| $r.outcome == "aborted" })
  let elapsed = ((date now) - $start | format duration sec | str replace -r '\.\d+' '')
  log $"phase ($phase): ($produced | length)/($entries | length) artifacts in ($elapsed)"
  { produced: $produced, missing: (($entries | length) - ($produced | length)), interrupted: $interrupted }
}

# Run a multi-agent review of <base>...<head>.
def "main run" [
  --manifest: path   # Pipeline manifest (JSON)
  --context: string  # Existing cue context slug in the repo's scope
  --base: string     # Base ref; the diff is <base>...<head>
  --head: string = "HEAD"  # Head ref to review
  -C: path           # Repository directory (default: current)
] {
  if $manifest == null { die "--manifest is required" }
  if $context == null { die "--context is required" }
  if $base == null { die "--base is required" }
  let dir = ($C | default $env.PWD | path expand)

  let top = (do { ^git -C $dir rev-parse --show-toplevel } | complete)
  if $top.exit_code != 0 { die $"not a git repository: ($dir)" }
  let repo = ($top.stdout | str trim)

  let status = (do { ^cue status -C $repo --context $context --json } | complete)
  if $status.exit_code != 0 { die $"context not found in this repository's scope: ($context)" }
  let st = ($status.stdout | from json)

  let m = (load-manifest ($manifest | path expand))
  let base_sha = (rev-parse $repo $base)
  let head_sha = (rev-parse $repo $head)

  let diff = (do { ^git -C $repo diff $"($base_sha)...($head_sha)" } | complete)
  if $diff.exit_code != 0 { die $"git diff failed: ($diff.stderr | str trim)" }
  if ($diff.stdout | str trim | is-empty) {
    log $"nothing to review: ($base)...($head) is empty"
    exit 0
  }
  let dirty = (^git -C $repo status --porcelain | str trim)
  if ($dirty | is-not-empty) {
    log "warning: working tree is dirty; uncommitted changes are not reviewed"
  }

  let tmp = (mktemp -t cue-review-diff.XXXXXX)
  $diff.stdout | save -f $tmp
  let added = (do { ^cue add -C $repo --type tmp --context $context --file $tmp review.diff } | complete)
  rm -f $tmp
  if $added.exit_code != 0 { die $"saving diff failed: ($added.stderr | str trim)" }
  let diff_path = ($added.stdout | lines | where {|l| $l | str ends-with "/review.diff" } | last | str trim)
  let run_id = ($diff_path | path dirname | path basename)

  let ctx = {
    slug: $context
    address: $st.address
    store: $st.store
    repo: $repo
    run_id: $run_id
    base: $base_sha
    head: $head_sha
    diff: $diff_path
  }
  log $"run ($run_id): ($base_sha | str substring 0..9)...($head_sha | str substring 0..9) in ($st.address)"

  mut inputs = []
  mut summary = []
  mut missing = 0
  for phase in $PHASES {
    let entries = ($m | get $phase)
    if ($entries | is-empty) { continue }
    let r = (run-phase $ctx $phase $entries $inputs)
    $summary = ($summary | append { phase: $phase, produced: $r.produced })
    $missing = $missing + $r.missing
    if $r.interrupted {
      log $"interrupted during ($phase); not starting further phases"
      print-summary $ctx $summary
      exit 130
    }
    if ($r.produced | is-empty) {
      log $"phase ($phase) produced no artifacts; stopping"
      print-summary $ctx $summary
      exit 1
    }
    $inputs = ($inputs ++ $r.produced)
  }

  print-summary $ctx $summary
  exit (if $missing > 0 { 1 } else { 0 })
}

def print-summary [ctx: record, summary: list] {
  print $"run_id: ($ctx.run_id)"
  print $"diff: ($ctx.address)/tmp/($ctx.run_id)/review.diff"
  for s in $summary {
    print $"($s.phase):"
    for p in $s.produced {
      print $"  ($ctx.address)/review/($ctx.run_id)/($p | path basename)"
    }
  }
}
