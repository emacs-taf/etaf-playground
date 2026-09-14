"""Exercise the diagnostic command against a real checked Workbench action."""
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProfileCommandTests(unittest.TestCase):
    def run_profile(self, scenario="row-toggle", samples="1", depth="256"):
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
                         ETAF_WORKBENCH_PROFILE_STACK_DEPTH=depth,
                         ETAF_WORKBENCH_PROFILE_OUTPUT=str(output)), check=False)
            return result, json.loads(output.read_text())

    def test_checked_action_has_separate_stages_and_recomputable_cpu_counts(self):
        result, report = self.run_profile()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["purpose"], "diagnostic-only")
        self.assertEqual((report["tasks"], report["page_size"]), (100, 10))
        self.assertGreater(len(report["operations"]), 1)
        self.assertEqual({row["action_index"] for row in report["operations"]}, {1})
        self.assertIn("event", {row["kind"] for row in report["operations"]})
        self.assertTrue(all(row["status"] == "success" for row in report["operations"]))
        self.assertEqual(len(report["cpu_profiles"]), 1)
        providers = {row["provider"] for row in report["operations"][0]["stages"]}
        self.assertTrue({"etaf", "ebox", "tp"}.issubset(providers))
        stacks = [stack for profile in report["cpu_profiles"] for stack in profile]
        self.assertEqual(report["max_stack_depth"], 256)
        self.assertEqual(report["depth_limit_samples"], sum(
            stack["samples"] for stack in stacks if stack["at_depth_limit"]))
        for stack in stacks:
            self.assertEqual(stack["at_depth_limit"], len(stack["frames"]) >= 256)
            self.assertNotEqual(stack["frames"][-1:], ["nil"])
        nearest = {}
        for stack in stacks:
            caller = next((name for name in stack["frames"]
                           if re.match(r"^(ebox|ecss|tp|etaf|wb)-", name)), None)
            if caller:
                nearest[caller] = nearest.get(caller, 0) + stack["samples"]
        self.assertEqual({row["function"]: row["samples"]
                          for row in report["nearest_package_callers"]}, nearest)
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

    def test_shallow_stacks_report_incomplete_caller_attribution(self):
        result, report = self.run_profile(depth="16")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(report["max_stack_depth"], 16)
        self.assertGreater(report["depth_limit_samples"], 0)
        self.assertAlmostEqual(report["depth_limit_percent"],
                               100 * report["depth_limit_samples"] / report["cpu_samples"])
        self.assertIn("omitted callers can be undercounted", result.stdout)

    def test_invalid_scenario_and_sample_count_fail_with_an_atomic_report(self):
        for scenario, samples in (("missing", "1"), ("row-toggle", "0"),
                                  ("row-toggle", "oops")):
            result, report = self.run_profile(scenario, samples)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(report["status"], "failed")
            self.assertTrue(report["error"])
            self.assertEqual(report["operations"], [])
            self.assertEqual(report["cpu_profiles"], [])

    def test_invalid_depth_fails_before_sampling(self):
        for depth in ("0", "1025", "oops"):
            result, report = self.run_profile(depth=depth)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(report["status"], "failed")
            self.assertEqual(report["cpu_profiles"], [])
            self.assertEqual(report["depth_limit_samples"], 0)


if __name__ == "__main__":
    unittest.main()
