"""Syntax-check every .ahk file in the repo with the engine's `check` command.

Usage: python tools/check_all.py ENGINE [PATH...]

Each file is parsed in its own throwaway process (parse has side effects such
as hotkey registration, so nothing is loaded into a long-lived engine).
Failures are printed as `file:line:col: message`; under GitHub Actions they
are also emitted as `::error` annotations. Exit status is the number of
failing files, capped at 1 for shells.

Skipped: dot-directories (.git, .claude, .history, .kilo, .vscode, ...), any
directory holding its own `.git` entry (a nested worktree or clone), the
SKIP_DIRS below, and everything in tests/ except the single-process suite.
A fresh checkout (CI) has no script in a dot-directory except the hooks'
fixture .claude/hooks/test-hooks-gui.ahk, which was always skipped, so these
rules only drop local agent worktrees and editor history.
"""

import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Directories that hold scratch, build output, or scripts that are
# deliberately invalid (crash-log and parse-error fixtures). Dot-directories
# are skipped by skipped_dir() below.
SKIP_DIRS = {"node_modules", "temp", "out", "drafts", "logs",
             "bin", "bin_debug", "bin_dev", "bin_harness", "bin_review", "tmp", "fixtures"}
SKIP_PREFIXES = ("build",)
# tests/ holds mostly hand-run fixtures; only the single-process suite is checked.
CHECKED_TEST_FILES = ("run.ahk", "Test.ahk")


def skipped_dir(directory):
    """True for a directory under ROOT whose scripts this checkout does not own."""
    name = directory.name
    if name.startswith(".") or name in SKIP_DIRS or name.startswith(SKIP_PREFIXES):
        return True
    # A worktree has a .git file and a nested clone a .git directory; either
    # way the directory is another checkout (for example a stale agent worktree).
    return os.path.lexists(directory / ".git")


def wanted(path):
    rel = path.relative_to(ROOT)
    parts = rel.parts
    directory = ROOT
    for part in parts[:-1]:
        directory = directory / part
        if skipped_dir(directory):
            return False
    if parts[0] == "tests":
        return len(parts) == 2 and (parts[1] in CHECKED_TEST_FILES or parts[1].endswith(".test.ahk"))
    return True


def collect(roots):
    """Every wanted .ahk file under roots, without descending into skipped directories."""
    found = set()
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            here = Path(dirpath)
            dirnames[:] = [d for d in dirnames if not skipped_dir(here / d)]
            found.update(here / f for f in filenames if f.lower().endswith(".ahk"))
    return sorted(p for p in found if wanted(p))


def check(engine, path):
    command = [str(engine), "/Headless", "/Diag=json", "check", str(path)]
    try:
        run = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=30, cwd=ROOT,
                             creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except subprocess.TimeoutExpired:
        return path, [{"file": str(path), "line": 0, "column": 0, "message": "check timed out"}]
    if run.returncode == 0:
        return path, []
    diagnostics = []
    for line in run.stderr.splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if item.get("kind") == "diagnostic":
            diagnostics.append(item)
    if not diagnostics:
        diagnostics.append({"file": str(path), "line": 0, "column": 0,
                            "message": f"check exited {run.returncode}: {run.stderr.strip()[:200]}"})
    return path, diagnostics


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    engine = Path(sys.argv[1]).resolve()
    if not engine.is_file():
        print(f"Engine does not exist: {engine}", file=sys.stderr)
        return 2
    roots = [Path(p).resolve() for p in sys.argv[2:]] or [ROOT]
    files = collect(roots)
    if not files:
        print("check_all: no .ahk files found", file=sys.stderr)
        return 2

    on_actions = os.environ.get("GITHUB_ACTIONS") == "true"
    failures = 0
    with ThreadPoolExecutor(max_workers=4) as pool:
        for path, diagnostics in pool.map(lambda p: check(engine, p), files):
            if not diagnostics:
                continue
            failures += 1
            rel = path.relative_to(ROOT).as_posix()
            for item in diagnostics:
                file = item.get("file") or rel
                try:
                    file = Path(file).resolve().relative_to(ROOT).as_posix()
                except ValueError:
                    pass
                message = item.get("message", "")
                if item.get("extra"):
                    message += f" ({item['extra']})"
                print(f"{file}:{item.get('line', 0)}:{item.get('column', 0)}: {message}")
                if on_actions:
                    print(f"::error file={file},line={item.get('line', 0)},col={item.get('column', 0)}"
                          f",title=check::{message}")
    print(f"check_all: {len(files) - failures}/{len(files)} files parse", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
