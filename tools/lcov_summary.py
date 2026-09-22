"""Merge LCOV tracefiles, print a per-file table, and emit a shields.io badge.

Usage:
    python tools/lcov_summary.py [--include REGEX] [--exclude REGEX]
        [--out merged.lcov] [--badge coverage.json] [--min PCT] FILE_OR_GLOB...

DA records for the same file and line are summed across inputs, so a suite that
runs one process per test (qa/run.ahk with AHK_QA_COVERAGE_DIR) merges with a
single-process suite (tests/run.ahk). Paths are shown relative to --root
(default: the current directory) with forward slashes; --include/--exclude
match against that relative form. Exit status is 1 when the total is below
--min, 2 when no data matched.
"""

import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


def parse_lcov(path, root):
    records = {}
    current = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith("SF:"):
                current = relative(line[3:], root)
                records.setdefault(current, defaultdict(int))
            elif line.startswith("DA:") and current is not None:
                number, hits = line[3:].split(",")[:2]
                records[current][int(number)] += int(hits)
            elif line == "end_of_record":
                current = None
    return records


def relative(path, root):
    try:
        rel = Path(path).resolve().relative_to(root)
        return rel.as_posix()
    except ValueError:
        return Path(path).as_posix()


def badge_color(pct):
    for threshold, color in ((90, "brightgreen"), (80, "green"), (70, "yellowgreen"),
                             (60, "yellow"), (40, "orange")):
        if pct >= threshold:
            return color
    return "red"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("inputs", nargs="+", help="LCOV files or globs")
    parser.add_argument("--root", default=".", help="directory paths are shown relative to")
    parser.add_argument("--include", help="regex; keep only matching files")
    parser.add_argument("--exclude", help="regex; drop matching files")
    parser.add_argument("--out", help="write the merged LCOV here")
    parser.add_argument("--badge", help="write a shields.io endpoint JSON here")
    parser.add_argument("--min", type=float, default=0.0, help="fail below this total percentage")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    files = []
    for pattern in args.inputs:
        matches = sorted(glob.glob(pattern, recursive=True))
        files.extend(matches if matches else [pattern])

    merged = {}
    for path in files:
        if not os.path.isfile(path):
            print(f"lcov_summary: missing input {path}", file=sys.stderr)
            continue
        for name, lines in parse_lcov(path, root).items():
            target = merged.setdefault(name, defaultdict(int))
            for number, hits in lines.items():
                target[number] += hits

    include = re.compile(args.include) if args.include else None
    exclude = re.compile(args.exclude) if args.exclude else None
    selected = {name: lines for name, lines in merged.items()
                if (not include or include.search(name)) and not (exclude and exclude.search(name))}
    if not selected:
        print("lcov_summary: no coverage records matched", file=sys.stderr)
        return 2

    rows = []
    total_found = total_hit = 0
    for name in sorted(selected):
        lines = selected[name]
        found = len(lines)
        hit = sum(1 for hits in lines.values() if hits)
        total_found += found
        total_hit += hit
        rows.append((name, found, hit))
    total_pct = 100.0 * total_hit / total_found if total_found else 0.0

    width = max(len(row[0]) for row in rows)
    print(f"{'file':<{width}}  {'lines':>6}  {'hit':>6}  {'%':>6}")
    for name, found, hit in rows:
        pct = 100.0 * hit / found if found else 0.0
        print(f"{name:<{width}}  {found:>6}  {hit:>6}  {pct:>5.1f}%")
    print(f"{'TOTAL':<{width}}  {total_found:>6}  {total_hit:>6}  {total_pct:>5.1f}%")

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(f"### Coverage: {total_pct:.1f}% ({total_hit}/{total_found} lines)\n\n")
            handle.write("| File | Lines | Hit | % |\n|---|---:|---:|---:|\n")
            for name, found, hit in rows:
                pct = 100.0 * hit / found if found else 0.0
                handle.write(f"| `{name}` | {found} | {hit} | {pct:.1f}% |\n")

    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
            for name in sorted(selected):
                lines = selected[name]
                handle.write(f"SF:{name}\n")
                for number in sorted(lines):
                    handle.write(f"DA:{number},{lines[number]}\n")
                handle.write(f"LF:{len(lines)}\nLH:{sum(1 for h in lines.values() if h)}\nend_of_record\n")

    if args.badge:
        payload = {"schemaVersion": 1, "label": "coverage",
                   "message": f"{total_pct:.0f}%", "color": badge_color(total_pct)}
        with open(args.badge, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)

    if total_pct < args.min:
        print(f"lcov_summary: {total_pct:.1f}% is below the required {args.min:.1f}%", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
