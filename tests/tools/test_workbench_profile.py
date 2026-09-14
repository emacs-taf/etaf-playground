"""Exercise the diagnostic command against a real checked Workbench action."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProfileCommandTests(unittest.TestCase):
    def run_profile(self, scenario="row-toggle", samples="1"):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "profile.json"
            command = [os.environ.get("EMACS", "emacs"), "-Q", "--batch"]
            for path in (ROOT, ROOT / "benchmarks", ROOT / "examples",
                         *(ROOT.parent / name for name in ("etaf", "etaf-ui", "ebox", "ecss", "tp"))):
                command.extend(["-L", str(path)])
            command.extend(["--eval", "(setq load-prefer-newer t native-comp-jit-compilation nil)",
                            "-l", str(ROOT / "benchmarks/profile-task-workbench.el"),
                            "-f", "etaf-workbench-profile-batch"])
            result = subprocess.run(
                command, cwd=ROOT, capture_output=True, text=True, timeout=120,
                env=dict(os.environ, ETAF_WORKBENCH_PROFILE_SCENARIO=scenario,
                         ETAF_WORKBENCH_PROFILE_SAMPLES=samples,
                         ETAF_WORKBENCH_PROFILE_OUTPUT=str(output)), check=False)
            return result, json.loads(output.read_text())

    def test_checked_action_has_separate_stages_and_recomputable_cpu_counts(self):
        result, report = self.run_profile()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["purpose"], "diagnostic-only")
        self.assertEqual((report["tasks"], report["page_size"]), (100, 10))
        self.assertEqual(len(report["operations"]), 1)
        self.assertEqual(len(report["cpu_profiles"]), 1)
        providers = {row["provider"] for row in report["operations"][0]["stages"]}
        self.assertTrue({"etaf", "ebox", "tp"}.issubset(providers))
        stacks = [stack for profile in report["cpu_profiles"] for stack in profile]
        self.assertGreater(report["cpu_samples"], 0)
        self.assertEqual(report["cpu_samples"], sum(stack["samples"] for stack in stacks))
        self.assertTrue(report["functions"])
        for row in report["functions"]:
            self.assertEqual(row["inclusive_samples"], sum(
                stack["samples"] for stack in stacks if row["function"] in stack["frames"]))
            self.assertEqual(row["self_samples"], sum(
                stack["samples"] for stack in stacks if stack["frames"][:1] == [row["function"]]))
        self.assertIn("not elapsed time", result.stdout)
        self.assertLess(len(result.stdout.splitlines()), 30)

    def test_invalid_scenario_and_sample_count_fail_with_an_atomic_report(self):
        for scenario, samples in (("missing", "1"), ("row-toggle", "0"),
                                  ("row-toggle", "oops")):
            result, report = self.run_profile(scenario, samples)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(report["status"], "failed")
            self.assertTrue(report["error"])
            self.assertEqual(report["operations"], [])
            self.assertEqual(report["cpu_profiles"], [])


if __name__ == "__main__":
    unittest.main()
