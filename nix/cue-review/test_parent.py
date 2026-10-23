"""Offline parent flag tests; no agents or real cue contexts are created."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("cue-review.nu")


class ParentTests(unittest.TestCase):
    def test_target_validation(self):
        for target, arg in [("pr", "123"), ("branch", "topic"),
                            ("commit", "HEAD"), ("range", "HEAD~1..HEAD")]:
            for args, message in [
                ([arg, arg, "--parent", "org/repo/work"], "single target"),
            ]:
                with self.subTest(target=target, args=args):
                    result = subprocess.run(["nu", str(SCRIPT), target, *args],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertIn(message, result.stderr)

    def test_parent_resolution(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stub = root / "cue"
            stub.write_text(
                "#!/usr/bin/env python3\n"
                "import json, sys\n"
                "assert sys.argv[1:] == ['status', '-C', "
                "sys.argv[3], '--context', 'work', '--json']\n"
                "if sys.argv[3].endswith('missing'):\n"
                " print('Context does not exist: work', file=sys.stderr)\n"
                " sys.exit(1)\n"
                "print(json.dumps({'address': 'org/repo/work'}))\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}")
            for repo, expected in [(root, 0), (root / 'missing', 2)]:
                result = subprocess.run(
                    ['nu', '-c', f'source {SCRIPT}; resolve-parent work 1 "{repo}"'],
                    env=env, capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, expected, result.stderr)
                if expected == 0:
                    self.assertEqual(result.stdout.strip(), 'org/repo/work')
                else:
                    self.assertIn('Context does not exist: work', result.stderr)

    def test_context_creation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stub = root / "cue"
            stub.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "with open(os.environ['CALLS'], 'a') as f:\n"
                " f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "if sys.argv[1] == 'status': sys.exit(int(os.environ['MISSING']))\n"
                "if sys.argv[1:3] == ['context', 'create']: "
                "sys.exit(int(os.environ['CREATE_EXIT']))\n"
            )
            stub.chmod(0o755)
            calls = root / "calls"
            for parent, missing, failed in [
                ('"org/repo/work"', True, False),
                ('null', True, False),
                ('"org/repo/work"', False, False),
                ('"org/repo/work"', True, True),
            ]:
                with self.subTest(parent=parent, missing=missing, failed=failed):
                    calls.write_text("")
                    env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                               CALLS=str(calls), MISSING=str(int(missing)),
                               CREATE_EXIT=str(int(failed)))
                    result = subprocess.run(
                        ["nu", "-c", f'source {SCRIPT}; '
                         f'ensure-context "{root}" review-topic "Review" {parent}'],
                        env=env, text=True, capture_output=True,
                    )
                    self.assertEqual(result.returncode, 2 if failed else 0,
                                     result.stderr)
                    commands = [json.loads(line) for line in calls.read_text().splitlines()]
                    creates = [c for c in commands if c[:2] == ["context", "create"]]
                    self.assertEqual(len(creates), int(missing))
                    if creates:
                        if parent == 'null':
                            self.assertNotIn('--parent', creates[0])
                        else:
                            i = creates[0].index('--parent')
                            self.assertEqual(creates[0][i + 1], 'org/repo/work')
                    if failed:
                        self.assertFalse(any(c[:2] == ['context', 'pin'] for c in commands))


if __name__ == "__main__":
    unittest.main()
