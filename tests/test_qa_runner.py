"""Process-level QA runner contracts. Usage: python tests/test_qa_runner.py ENGINE."""

import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else ROOT / "bin/AutoHotkey64.exe"


def process_alive(pid):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x100000, False, pid)
    if not handle:
        return False
    try:
        return kernel.WaitForSingleObject(handle, 0) == 258
    finally:
        kernel.CloseHandle(handle)


class QaRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ahk-qa-contract-")
        self.addCleanup(self.temp.cleanup)
        self.qa = Path(self.temp.name) / "qa"
        (self.qa / "tests").mkdir(parents=True)
        for name in ("run.ahk", "Harness.ahk", "Assert.ahk"):
            shutil.copy2(ROOT / "qa" / name, self.qa / name)

    def fixture(self, name, source):
        (self.qa / "tests" / f"test_{name}.ahk").write_text(source, encoding="utf-8")

    def run_suite(self, timeout_ms=2000):
        env = dict(os.environ, AHK_QA_TIMEOUT_MS=str(timeout_ms))
        child = subprocess.Popen(
            [str(ENGINE), "/Headless", "/ErrorStdOut", str(self.qa / "run.ahk")],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=env, creationflags=subprocess.CREATE_NO_WINDOW,
        )
        try:
            output, _ = child.communicate(timeout=6)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"],
                           capture_output=True, timeout=5)
            output, _ = child.communicate(timeout=5)
            self.fail("QA runner exceeded its child timeout: " + output.decode("utf-8", "replace"))
        return child.returncode, output.decode("utf-8", "replace")

    def test_empty_discovery_is_failure(self):
        code, output = self.run_suite()
        self.assertNotEqual(code, 0, output)
        self.assertIn("no test files", output)

    def test_success_requires_zero_exit_and_passing_summary(self):
        self.fixture("pass", 'Print("qa: 2 passed, 0 failed")\nExitApp(0)')
        code, output = self.run_suite()
        self.assertEqual(code, 0, output)
        self.assertIn("[PASS] test_pass.ahk", output)

    def test_nonzero_exit_cannot_be_hidden_by_passing_summary(self):
        self.fixture("mismatch", 'Print("qa: 2 passed, 0 failed")\nExitApp(23)')
        code, output = self.run_suite()
        self.assertNotEqual(code, 0, output)
        self.assertNotIn("[PASS] test_mismatch.ahk", output)

    def test_failure_count_must_agree_with_exit_code(self):
        self.fixture("mismatch", 'Print("qa: 0 passed, 2 failed")\nExitApp(0)')
        code, output = self.run_suite()
        self.assertNotEqual(code, 0, output)
        self.assertIn("[CRASH] test_mismatch.ahk", output)

    def test_failure_count_is_preserved(self):
        self.fixture("fail", 'Print("qa: 1 passed, 2 failed")\nExitApp(2)')
        code, output = self.run_suite()
        self.assertEqual(code, 2, output)
        self.assertIn("[FAIL] test_fail.ahk", output)

    def test_child_receives_headless_flag(self):
        self.fixture("headless", '''
command := StrGet(DllCall("GetCommandLineW", "ptr"), "UTF-16")
ok := InStr(command, "/Headless") != 0
Print("qa: {} passed, {} failed", ok, !ok)
ExitApp(!ok)
''')
        code, output = self.run_suite()
        self.assertEqual(code, 0, output)

    def test_timeout_kills_descendants_and_continues_suite(self):
        marker = self.qa / "child.pid"
        self.fixture("a_timeout", f'''
#SingleInstance Off
if A_Args.Length {{
    FileAppend(ProcessExist(), "{marker}")
    Loop
        Sleep(1000)
}}
Run('"' A_AhkPath '" /Headless /ErrorStdOut "' A_ScriptFullPath '" child', , "Hide")
Loop
    Sleep(1000)
''')
        self.fixture("z_after", 'Print("qa: 1 passed, 0 failed")\nExitApp(0)')
        try:
            code, output = self.run_suite(timeout_ms=600)
            self.assertNotEqual(code, 0, output)
            self.assertIn("[TIMEOUT] test_a_timeout.ahk", output)
            self.assertIn("[PASS] test_z_after.ahk", output)
            self.assertTrue(marker.exists(), "Grandchild did not start")
            self.assertFalse(process_alive(int(marker.read_text())), "Timed-out grandchild survived")
        finally:
            if marker.exists() and process_alive(int(marker.read_text())):
                subprocess.run(["taskkill", "/PID", marker.read_text(), "/T", "/F"],
                               capture_output=True, timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
