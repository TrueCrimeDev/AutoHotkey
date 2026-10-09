"""Run the release's native regression gate. Usage: python tests/run_console_gate.py ENGINE."""

import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
# A Python suite that exits 77 did not run, e.g. test_debugger_fatal.py on an engine without the
# fix it checks. (Engine suites are not read this way: qa/run.ahk exits with its failure count.)
# That is a skip locally, but under CI (CI=true) the engine was just built from this tree, so a
# skip means the suite's guard no longer recognizes it, and the gate fails.
SKIPPED = 77


def suite_name(command):
    return next((Path(part).name for part in command[1:] if part.endswith((".py", ".ahk"))),
                Path(command[0]).name)


def main():
    if len(sys.argv) != 2:
        print("Usage: python tests/run_console_gate.py ENGINE", file=sys.stderr)
        return 2
    engine = Path(sys.argv[1]).resolve()
    if not engine.is_file():
        print(f"Engine does not exist: {engine}", file=sys.stderr)
        return 2
    suites = [
        [str(engine), "/Headless", "/ErrorStdOut", str(ROOT / "qa/run.ahk")],
        *[[str(engine), "test", "/Headless", str(ROOT / "tests" / suite)] for suite in (
            "test_eval.ahk", "test_eval_gated.ahk"
        )],
        [str(engine), "test", "/Headless", "/Eval", str(ROOT / "tests/test_eval_flag.ahk")],
        *[[sys.executable, str(ROOT / "tests" / suite), str(engine)] for suite in (
            "test_qa_runner.py", "test_console_cli.py", "test_console_repl.py", "test_mcp_protocol.py",
            "test_console_trace.py", "test_console_coverage.py", "test_runtime_regressions.py",
            "test_process_mcp_regressions.py", "test_debugger_fatal.py", "test_debugger_property_data.py"
        )],
        [str(engine), "test", "/Headless", str(ROOT / "tests/run.ahk")],
    ]
    if os.name == "nt" and engine.stem.lower().endswith("console"):
        suites.append([sys.executable, str(ROOT / "tests/test_powershell_cli.py"),
                       "--wrapper", str(ROOT / "tools/ahk.ps1"), "--engine", str(engine)])
    failures = 0
    skipped = []
    strict = os.environ.get("CI", "").lower() == "true"
    for command in suites:
        print("Running: " + subprocess.list2cmdline(command), flush=True)
        child = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            output, _ = child.communicate(timeout=180)
            code = child.returncode
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"],
                               capture_output=True, timeout=10)
            else:
                child.kill()
            child.wait(timeout=10)
            print("FAIL: suite exceeded 180 seconds", file=sys.stderr)
            failures += 1
            continue
        print(output.decode("utf-8", "replace"), end="", flush=True)
        skip = code == SKIPPED and command[0] == sys.executable
        if skip and not strict:
            print(f"SKIP: {suite_name(command)} did not run (exit {SKIPPED}); its reason is above",
                  flush=True)
            skipped.append(suite_name(command))
        elif skip:
            print(f"FAIL: {suite_name(command)} skipped under CI (exit {SKIPPED}); the engine built "
                  "here must carry what the suite checks", file=sys.stderr)
            failures += 1
        elif code:
            print(f"FAIL: suite exited {code}", file=sys.stderr)
            failures += 1
    summary = f"Console gate: {len(suites) - failures - len(skipped)}/{len(suites)} suites passed"
    if skipped:
        summary += f", {len(skipped)} skipped ({', '.join(skipped)})"
    print(summary, flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
