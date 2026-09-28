"""Exercise the Desktop GUI command contract without contacting a real Emacs."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class DesktopGuiRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        scripts = self.root / "etaf-playground" / "scripts"
        scripts.mkdir(parents=True)
        self.runner = scripts / "run-desktop-gui-verification.sh"
        shutil.copyfile(ROOT / "scripts" / self.runner.name, self.runner)
        (scripts / "desktop-gui-scenarios.el").touch()
        providers = self.root / "etaf" / "scripts"
        providers.mkdir(parents=True)
        (providers / "emacs-gui-verifier.el").touch()
        (providers / "capture-emacs-window.sh").touch()
        self.calls = self.root / "client-calls.jsonl"
        self.run_dir = self.root / 'evidence with "quotes"'
        self.client = self.root / "fake emacsclient"
        self.client.write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

with Path(os.environ["FAKE_CLIENT_CALLS"]).open("a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
expression = sys.argv[-1]
if expression.startswith("(list :pid"):
    print('(:pid 123 :graphic t :visible t :buffer "test")')
else:
    if os.environ.get("FAKE_CLIENT_PENDING") != "1":
        directory = Path(os.environ["FAKE_RUN_DIR"])
        (directory / "result.json").write_text('{"status":"passed"}')
    print('"scheduled"')
''', encoding="utf-8")
        self.client.chmod(0o755)
        self.env = dict(os.environ, EMACSCLIENT=str(self.client),
                        FAKE_CLIENT_CALLS=str(self.calls),
                        FAKE_RUN_DIR=str(self.run_dir), GUI_TIMEOUT="5")

    def run_command(self, *arguments, **environment):
        return subprocess.run(
            ["sh", str(self.runner), *arguments],
            env=dict(self.env, **environment), capture_output=True, text=True,
            timeout=10, check=False)

    def read_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def assert_scheduled(self, result, scenario):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("GUI ASSERTIONS PASS", result.stdout)
        calls = self.read_calls()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][0], "--eval")
        self.assertIn(":graphic (display-graphic-p)", calls[0][1])
        self.assertEqual(calls[1][0], "--eval")
        invocation = (f"(etaf-desktop-gui-run {json.dumps(str(self.run_dir))} "
                      f"'{scenario})")
        self.assertIn(invocation, calls[1][1])

    def test_default_schedules_shell_through_emacsclient_override(self):
        result = self.run_command("run", "--run-dir", str(self.run_dir))
        self.assert_scheduled(result, "shell")

    def test_demo_schedules_selected_scenario(self):
        result = self.run_command("run", "--scenario", "demo", "--run-dir",
                                  str(self.run_dir))
        self.assert_scheduled(result, "demo")

    def test_explicit_shell_schedules_shell(self):
        result = self.run_command("run", "--run-dir", str(self.run_dir),
                                  "--scenario", "shell")
        self.assert_scheduled(result, "shell")

    def test_unknown_scenario_is_rejected_before_contacting_server(self):
        result = self.run_command("run", "--scenario", "unknown", "--run-dir",
                                  str(self.run_dir))
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown Desktop GUI scenario: unknown", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.run_dir.exists())

    def test_existing_evidence_is_preserved_without_contacting_server(self):
        for name in ("manifest.jsonl", "result.json"):
            with self.subTest(evidence=name):
                self.run_dir.mkdir(exist_ok=True)
                evidence = self.run_dir / name
                evidence.write_text("existing evidence", encoding="utf-8")
                result = self.run_command("run", "--scenario", "demo",
                                          "--run-dir", str(self.run_dir))
                self.assertEqual(result.returncode, 1)
                self.assertIn("already contains GUI evidence", result.stderr)
                self.assertFalse(self.calls.exists())
                self.assertEqual(evidence.read_text(), "existing evidence")
                evidence.unlink()

    def test_pending_scenario_keeps_external_timeout(self):
        result = self.run_command("run", "--scenario", "demo", "--run-dir",
                                  str(self.run_dir), GUI_TIMEOUT="0",
                                  FAKE_CLIENT_PENDING="1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("scenario timed out", result.stderr)
        self.assertEqual(len(self.read_calls()), 2)
        self.assertFalse((self.run_dir / "result.json").exists())


if __name__ == "__main__":
    unittest.main()
