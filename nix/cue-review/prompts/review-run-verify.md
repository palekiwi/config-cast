Verify the candidate findings for the diff named in the <review-run> block
below. The merge artifact under `inputs` (the one with a `candidates`
array) is your work list; the reviewer artifacts are listed only so you
can look up a `source_ids` entry when a candidate is unclear.

1. For each candidate, inspect the actual source with ranged `read` and
   check its `unverified` claims; decide verified, refuted, or
   unconfirmable. Where the merge recorded `disagreements`, settle the
   severity from what you verified.
2. Save the result with the `cue-review` tool using exactly the `filename`
   and `context` given under `output`. Set `metadata.run_id`, `base`,
   `head`, and `reviewed_diff` from the block.
3. Reply with the saved path and the counts of verified, refuted, and
   unconfirmable findings, plus actionable findings by severity with exact
   `file:line_start-line_end` locations.
