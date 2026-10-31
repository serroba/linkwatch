"""Report line coverage per module and file, and fail when a gate is not met.

Usage:
  check_coverage.py REPORT [--gate DIR=MIN] [--file-floor DIR=MIN] [--report DIR] [--lowest N]

--gate fails when DIR's overall line coverage is below MIN percent, --file-floor when any
file in DIR is below MIN, and --report only lists DIR. With GITHUB_STEP_SUMMARY set, a
Markdown table is appended to the CI job summary.
"""

import argparse
import json
import os
import pathlib
import sys


def parse_pair(text):
    directory, _, minimum = text.partition("=")
    return directory, float(minimum)


def collect(report, directories):
    files = json.loads(pathlib.Path(report).read_text())["data"][0]["files"]
    modules = {directory: [] for directory in directories}
    for entry in files:
        for directory in directories:
            marker = f"/{directory}/"
            if marker in entry["filename"]:
                lines = entry["summary"]["lines"]
                name = entry["filename"].split(marker, 1)[1]
                modules[directory].append((name, lines["covered"], lines["count"]))
    return modules


def percent(covered, total):
    return 100 * covered / total if total else 0.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report")
    parser.add_argument("--gate", action="append", default=[], type=parse_pair)
    parser.add_argument("--file-floor", action="append", default=[], type=parse_pair)
    parser.add_argument("--report", dest="reported", action="append", default=[])
    parser.add_argument("--lowest", type=int, default=5)
    args = parser.parse_args()

    gates = dict(args.gate)
    floors = dict(args.file_floor)
    directories = list(dict.fromkeys([*gates, *floors, *args.reported]))
    modules = collect(args.report, directories)

    failures = []
    text = []
    summary = ["## Test coverage", "", "| Module | Lines | Coverage | Minimum |", "|---|---|---|---|"]
    lowest = []
    for directory in directories:
        files = modules[directory]
        covered = sum(file[1] for file in files)
        total = sum(file[2] for file in files)
        minimum = gates.get(directory)
        if total == 0:
            text.append(f"{directory}: not measured")
            summary.append(f"| {directory} | — | not measured | {minimum or '—'} |")
            if minimum is not None:
                failures.append(f"{directory}: no coverage data")
            continue
        value = percent(covered, total)
        text.append(f"{directory}: {value:.1f}% line coverage ({covered}/{total})"
                    + (f", minimum {minimum:.0f}%" if minimum is not None else ""))
        summary.append(f"| {directory} | {covered}/{total} | {value:.1f}% | "
                       + (f"{minimum:.0f}%" if minimum is not None else "report only") + " |")
        if minimum is not None and value < minimum:
            failures.append(f"{directory}: {value:.1f}% is below {minimum:.0f}%")
        floor = floors.get(directory)
        for name, file_covered, file_total in files:
            file_value = percent(file_covered, file_total)
            lowest.append((file_value, f"{directory}/{name}", file_covered, file_total))
            if floor is not None and file_total and file_value < floor:
                failures.append(f"{directory}/{name}: {file_value:.1f}% is below the {floor:.0f}% file floor")

    lowest.sort()
    if lowest:
        text.append(f"Lowest {min(args.lowest, len(lowest))} files:")
        summary += ["", "| Lowest files | Lines | Coverage |", "|---|---|---|"]
        for value, name, covered, total in lowest[: args.lowest]:
            text.append(f"  {value:5.1f}%  {name} ({covered}/{total})")
            summary.append(f"| {name} | {covered}/{total} | {value:.1f}% |")
    text += [f"FAIL {failure}" for failure in failures]
    print("\n".join(text))

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write("\n".join(summary + [f"- ❌ {failure}" for failure in failures]) + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
