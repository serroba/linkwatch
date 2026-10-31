"""Fail when line coverage of a source directory drops below a minimum."""

import json
import pathlib
import sys


def main():
    report, directory, minimum = sys.argv[1], sys.argv[2], float(sys.argv[3])
    files = json.loads(pathlib.Path(report).read_text())["data"][0]["files"]
    covered = total = 0
    for entry in files:
        if f"/{directory}/" in entry["filename"]:
            lines = entry["summary"]["lines"]
            covered += lines["covered"]
            total += lines["count"]
    if total == 0:
        print(f"No coverage data for {directory}.")
        return 1
    percent = 100 * covered / total
    print(f"{directory}: {percent:.1f}% line coverage ({covered}/{total}), minimum {minimum:.0f}%.")
    return percent < minimum


if __name__ == "__main__":
    sys.exit(main())
