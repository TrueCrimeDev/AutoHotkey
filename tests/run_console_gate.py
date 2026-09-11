"""Run the release's native regression gate. Usage: python tests/run_console_gate.py ENGINE."""

import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


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
            "test_console_trace.py"
        )],
    ]
    failures = 0
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
        if code:
            print(f"FAIL: suite exited {code}", file=sys.stderr)
            failures += 1
    print(f"Console gate: {len(suites) - failures}/{len(suites)} suites passed", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
