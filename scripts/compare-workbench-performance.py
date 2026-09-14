#!/usr/bin/env python3
"""Compare complete Workbench batch samples with a previous checkpoint."""

import argparse
import json
import math
import sys
from pathlib import Path

SCENARIOS = {"row-toggle", "theme-toggle", "focus-add"}
ENVIRONMENT = ("schema", "workload", "tasks", "page_size", "viewport_width",
               "viewport_height", "warmups", "samples", "timing", "emacs",
               "machine", "system", "native", "evaluator_hash", "app_compiled", "runtime_compiled")


def read_report(path):
    report = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(report, dict):
        raise ValueError(f"{path}: expected a report object")
    if report.get("status") not in ("passed", "failed"):
        raise ValueError(f"{path}: unfinished workload")
    if report.get("error"):
        raise ValueError(f"{path}: workload failed: {report['error']}")
    if (report.get("schema"), report.get("workload"), report.get("tasks"),
        report.get("page_size"), report.get("warmups"), report.get("samples")) != (
            1, "task-workbench", 100, 10, 5, 30):
        raise ValueError(f"{path}: incompatible workload or sample counts")
    if any(key not in report for key in ENVIRONMENT):
        raise ValueError(f"{path}: incomplete environment")
    rows = report.get("scenarios", [])
    if (not isinstance(rows, list) or len(rows) != len(SCENARIOS)
            or any(not isinstance(row, dict) for row in rows)
            or {row.get("name") for row in rows} != SCENARIOS):
        raise ValueError(f"{path}: incomplete or duplicate scenario coverage")
    statistics = {}
    for row in rows:
        samples = row.get("samples_ms", [])
        if not isinstance(samples, list) or len(samples) != 30 or any(
            type(value) not in (int, float) or not math.isfinite(value) or value < 0
            for value in samples
        ):
            raise ValueError(f"{path}: invalid raw samples for {row['name']}")
        ordered = sorted(samples)
        statistics[row["name"]] = (ordered[28], ordered[29])
    return report, statistics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline")
    parser.add_argument("current")
    args = parser.parse_args()
    try:
        baseline, previous = read_report(args.baseline)
        current, measured = read_report(args.current)
        if any(baseline[key] != current[key] for key in ENVIRONMENT):
            raise ValueError("environment or workload differs between reports")
        regressed = False
        for name in sorted(SCENARIOS):
            deltas = [new - old for old, new in zip(previous[name], measured[name])]
            failed = any(delta > 2.0 for delta in deltas)
            regressed |= failed
            print(f"{name} p95={deltas[0]:+.3f}ms max={deltas[1]:+.3f}ms "
                  f"{'REGRESSED' if failed else 'OK'}")
        absolute_failed = any(max(values) > 50.0 for values in measured.values())
        print(f"comparison={'FAILED' if regressed else 'PASSED'} "
              f"absolute={'FAILED' if absolute_failed else 'PASSED'}")
        return int(regressed or absolute_failed)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"ERROR {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
