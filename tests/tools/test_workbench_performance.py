"""Public command/report contracts for Workbench performance comparison."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/compare-workbench-performance.py"


class ComparisonTests(unittest.TestCase):
    def report(self, value=10):
        return dict(status="passed", schema=1, workload="task-workbench", tasks=100, page_size=10,
                    viewport_width=1413, viewport_height=62, warmups=5, samples=30,
                    timing="batch-dispatch-to-publication", emacs="test",
                    machine="fixture", system="fixture", native=None, error=None,
                    evaluator_hash="fixture", app_compiled=True, runtime_compiled=True,
                    scenarios=[dict(name=name, samples_ms=[value] * 30,
                                    p95_ms=0, max_ms=0)
                               for name in ("row-toggle", "theme-toggle", "focus-add")])

    def compare(self, before, after):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ("before.json", "after.json")]
            for path, report in zip(paths, (before, after)):
                path.write_text(json.dumps(report), encoding="utf-8")
            return subprocess.run([sys.executable, str(SCRIPT), *map(str, paths)],
                                  capture_output=True, text=True, check=False)

    def test_raw_samples_control_relative_and_absolute_results(self):
        self.assertEqual(self.compare(self.report(), self.report(12)).returncode, 0)
        result = self.compare(self.report(), self.report(13))
        self.assertEqual(result.returncode, 1)
        self.assertIn("comparison=FAILED absolute=PASSED", result.stdout)
        result = self.compare(self.report(60), self.report(59))
        self.assertEqual(result.returncode, 1)
        self.assertIn("comparison=PASSED absolute=FAILED", result.stdout)

    def test_missing_and_nonfinite_samples_are_rejected(self):
        for samples in ([10] * 29, [float("nan")] * 30, [True] * 30):
            report = self.report()
            report["scenarios"][0]["samples_ms"] = samples
            self.assertEqual(self.compare(self.report(), report).returncode, 2)

    def test_changed_environment_failed_workload_and_duplicate_rows_are_rejected(self):
        for key, value in (("machine", "different"), ("evaluator_hash", "changed"),
                           ("error", "failed action"), ("status", "running")):
            report = self.report()
            report[key] = value
            self.assertEqual(self.compare(self.report(), report).returncode, 2)
        report = self.report()
        report["scenarios"][1] = report["scenarios"][0]
        self.assertEqual(self.compare(self.report(), report).returncode, 2)


if __name__ == "__main__":
    unittest.main()
