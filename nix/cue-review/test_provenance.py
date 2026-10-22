"""Offline receipt/provenance tests; run in the nix/ devshell."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("cue-review.nu")


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        stub = self.bin / "cue-agent"
        stub.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, sys\n"
            "for name in json.loads(os.environ['ARTIFACTS']):\n"
            " p = pathlib.Path(os.environ['OUTPUT']) / name\n"
            " p.parent.mkdir(parents=True, exist_ok=True)\n"
            " p.write_text('{}')\n"
            "print(os.environ['RECEIPT'])\n"
            "sys.exit(int(os.environ.get('AGENT_EXIT', '0')))\n"
        )
        stub.chmod(0o755)
        self.output = self.root / "scope" / "ctx" / "review" / "run"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        OUTPUT=str(self.output), ARTIFACTS="[]", RECEIPT="{}")

    def nu(self, code):
        result = subprocess.run(
            ["nu", "-c", f"source {SCRIPT}; let result = (do {{ {code} }}); "
             'print "TEST_RESULT"; $result | to json'],
            env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout.split("TEST_RESULT\n", 1)[1])

    def phase(self, runs, artifacts=(), exit_code=0, raw=None):
        self.env.update(
            RECEIPT=raw if raw is not None else json.dumps({
                "runs": runs, "batch_id": "batch", "harness": "pi",
                "harness_version": "test",
            }),
            ARTIFACTS=json.dumps(list(artifacts)), AGENT_EXIT=str(exit_code),
        )
        ctx = dict(store=str(self.root), address="scope/ctx", slug="ctx",
                   run_id="run", repo=str(self.root), head="abc", base="def", diff="diff")
        entries = [dict(name=n, agent="reviewer", prompt="review", model="alias",
                        thinking=None, system_prompt=None) for n in ["one", "two"]]
        return self.nu(
            f"let ctx = ('{json.dumps(ctx)}' | from json); "
            f"let entries = ('{json.dumps(entries)}' | from json); "
            "run-phase $ctx reviewers $entries []"
        )

    def test_receipts_keep_metrics_not_response(self):
        runs = [dict(run_id="a", model="configured-id", outcome="completed",
                     duration_ms=25, cost_usd=0, tokens_input=10,
                     response="private response"),
                dict(run_id="b", outcome="timeout", error="deadline")]
        result = self.phase(runs, ["reviewers-one.json"])
        entries = result["provenance"]["entries"]
        self.assertEqual(entries[0]["receipt"]["model"], "configured-id")
        self.assertEqual(entries[0]["requested_model"], "alias")
        self.assertNotIn("response", entries[0]["receipt"])
        self.assertIsNone(entries[1]["receipt"]["cost_usd"])
        self.assertEqual(entries[1]["receipt"]["outcome"], "timeout")
        self.assertFalse(entries[1]["artifact_present"])
        self.assertEqual(result["missing"], 1)

    def test_missing_receipt_does_not_invent_interrupt(self):
        result = self.phase([], ["reviewers-one.json"], exit_code=1, raw="broken")
        self.assertFalse(result["interrupted"])
        self.assertTrue(result["receipt_missing"])
        entry = result["provenance"]["entries"][0]
        self.assertTrue(entry["artifact_present"])
        self.assertIsNone(entry["receipt"])

    def test_aborted_receipt_preserves_artifact(self):
        result = self.phase([{"outcome": "aborted"}], ["reviewers-one.json"], 130)
        self.assertTrue(result["interrupted"])
        self.assertEqual(len(result["produced"]), 1)
        self.assertTrue(result["receipt_missing"])

    def test_engine_persists_phase_before_stopping(self):
        repo = self.root / "repo"
        repo.mkdir()
        def git(*args):
            return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()
        git("init", "-q")
        git("-c", "user.name=Test", "-c", "user.email=test@example.test",
            "commit", "--allow-empty", "-qm", "base")
        base = git("rev-parse", "HEAD")
        (repo / "file").write_text("change")
        git("add", "file")
        git("-c", "user.name=Test", "-c", "user.email=test@example.test",
            "commit", "-qm", "head")
        head = git("rev-parse", "HEAD")
        stub = self.bin / "cue"
        stub.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, shutil, sys\n"
            "root = pathlib.Path(os.environ['STORE'])\n"
            "args = sys.argv\n"
            "if args[1] == 'status':\n"
            " print(json.dumps({'address':'scope/ctx','store':str(root)}))\n"
            "else:\n"
            " kind = args[args.index('--type')+1]\n"
            " dest = root / 'scope/ctx' / kind / args[-1]\n"
            " if kind == 'tmp': dest = root / 'tmp/run/review.diff'\n"
            " dest.parent.mkdir(parents=True, exist_ok=True)\n"
            " shutil.copyfile(args[args.index('--file')+1], dest)\n"
            " print(dest)\n"
        )
        stub.chmod(0o755)
        manifest = self.root / "default.json"
        manifest.write_text(json.dumps({
            "reviewers": [{"name": "one", "agent": "reviewer", "prompt": "review"}],
            "verifiers": [{"name": "verify", "agent": "verifier", "prompt": "verify"}],
        }))
        self.env.update(STORE=str(self.root), TMUX_PANE="", RECEIPT=json.dumps({
            "runs": [{"run_id": "a", "outcome": "failed", "error": "test failure"}]
        }))
        result = self.nu(f"run-review {manifest} ctx {base} {head} {repo}")
        self.assertEqual(result, 1)
        record = json.loads((self.output / "run.json").read_text())
        self.assertEqual(record["state"], "failed")
        self.assertEqual(record["phases"][0]["entries"][0]["receipt"]["error"], "test failure")
        self.assertEqual(record["phases"][2]["state"], "skipped")

        for phases in [["reviewers", "merge", "verifiers"], ["reviewers"]]:
            with self.subTest(phases=phases):
                shutil.rmtree(self.output)
                manifest.write_text(json.dumps({phase: [
                    {"name": "one", "agent": "reviewer", "prompt": "review"}
                ] for phase in phases}))
                self.env.update(
                    ARTIFACTS=json.dumps([f"{phase}-one.json" for phase in phases]),
                    RECEIPT=json.dumps({"runs": [{"run_id": "a", "outcome": "completed"}]}),
                )
                self.assertEqual(self.nu(f"run-review {manifest} ctx {base} {head} {repo}"), 0)
                record = json.loads((self.output / "run.json").read_text())
                self.assertEqual(record["state"], "completed")
                for phase in record["phases"]:
                    expected = "finished" if phase["phase"] in phases else "skipped"
                    self.assertEqual(phase["state"], expected)
                if "verifiers" in phases:
                    self.assertEqual(len(record["phases"][2]["entries"][0]["inputs"]), 2)

    def test_observed_models_and_requests_are_not_self_reported(self):
        events = self.root / "events.jsonl"
        events.write_text("\n".join([
            json.dumps({"type": "message_end", "message": {
                "role": "assistant", "provider": "provider", "model": "runtime-id"}}),
            json.dumps({"type": "tool_execution_start", "toolName": "read",
                        "args": {"path": "src/lib.rs", "offset": 10}}),
            json.dumps({"type": "tool_execution_start", "toolName": "grep",
                        "args": {"path": "src", "pattern": "private pattern"}}),
            json.dumps({"type": "tool_execution_start", "toolName": "bash",
                        "args": {"command": "private command"}}),
            "{invalid",
        ]))
        observed = self.nu(f'observed-activity {{run_path: "{self.root}"}}')
        self.assertEqual(observed["models"], [{"provider": "provider", "model": "runtime-id"}])
        self.assertEqual(observed["requests"], [
            {"tool": "read", "path": "src/lib.rs"}, {"tool": "grep", "path": "src"}])
        self.assertEqual(observed["malformed_lines"], 1)
        self.assertNotIn("private", json.dumps(observed))

    def test_event_limits_and_missing_stream(self):
        absent = self.nu(f'observed-activity {{run_path: "{self.root}"}}')
        self.assertEqual(absent["status"], "unavailable")
        (self.root / "events.jsonl").write_text('{"type":"other"}\n' * 10001)
        limited = self.nu(f'observed-activity {{run_path: "{self.root}", events_truncated: true}}')
        self.assertTrue(limited["events_limited"])
        self.assertTrue(limited["stream_truncated"])

    def test_request_limit_counts_only_omitted_unique_requests(self):
        for count in [500, 501]:
            with self.subTest(count=count):
                events = [json.dumps({"type": "tool_execution_start", "toolName": "read",
                                      "args": {"path": f"file-{i}"}}) for i in range(count)]
                (self.root / "events.jsonl").write_text("\n".join(events + [events[0]]))
                result = self.nu(f'observed-activity {{run_path: "{self.root}"}}')
                self.assertEqual(len(result["requests"]), 500)
                self.assertEqual(result["requests_limited"], count > 500)

    def test_summary_write_failure_is_visible(self):
        result = self.nu(
            f'try {{ save-run-record {self.root}/absent/run.json {{state: "running"}}; false }} '
            'catch { true }'
        )
        self.assertTrue(result)

    def test_atomic_summary_replacement(self):
        path = self.root / "run.json"
        path.write_text('{"state":"running"}')
        result = self.nu(f'save-run-record {path} {{state: "completed"}}; open {path}')
        self.assertEqual(result, {"state": "completed"})
        self.assertEqual(list(self.root.glob("run.json.*")), [])


if __name__ == "__main__":
    unittest.main()
