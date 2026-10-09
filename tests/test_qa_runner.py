"""Process-level QA runner contracts. Usage: python tests/test_qa_runner.py ENGINE."""

import ctypes
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


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

    def run_suite(self, timeout_ms=2000, junit=None):
        env = dict(os.environ, AHK_QA_TIMEOUT_MS=str(timeout_ms))
        env.pop("AHK_QA_JUNIT", None)
        if junit is not None:
            env["AHK_QA_JUNIT"] = str(junit)
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

    SUMMARY = re.compile(r"^qa: (\d+) passed, (\d+) failed, (\d+) crashed across (\d+) file\(s\)$", re.M)

    def test_junit_report_matches_summary(self):
        self.fixture("asserts", "\n".join([
            "#Include ..\\Assert.ahk",
            'Assert.eq(1, 1, "one is one")',
            'Assert.eq(1, 2, "one is two")',
            'Assert.truthy(1, "truthy")',
            'Print("  SKIP needs a screen")',
            "Assert.Summary()",
        ]))
        self.fixture("crash", 'throw Error("boom")')
        self.fixture("summary_only", 'Print("qa: 1 passed, 2 failed")\nExitApp(2)')
        report = Path(self.temp.name) / "reports" / "qa.xml"
        code, output = self.run_suite(junit=report)
        self.assertEqual(code, 4, output)
        summary = self.SUMMARY.search(output)
        self.assertIsNotNone(summary, output)
        passed, failed, crashed, files = map(int, summary.groups())
        self.assertFalse(list(report.parent.glob("*.tmp")), "temp file left beside the report")

        root = ET.parse(report).getroot()
        self.assertEqual(root.tag, "testsuites")
        suites = root.findall("testsuite")
        self.assertEqual(len(suites), files)
        self.assertEqual(len(suites), 3)
        totals = {key: int(root.get(key)) for key in ("tests", "failures", "errors", "skipped")}
        self.assertEqual(totals["failures"] + totals["errors"], failed)
        self.assertEqual(totals["errors"], crashed)
        self.assertEqual(totals["tests"] - totals["failures"] - totals["errors"] - totals["skipped"], passed)
        for suite in suites:
            name = suite.get("name")
            self.assertEqual(len(suite.findall("testcase")), int(suite.get("tests")), name)
            self.assertEqual(len(suite.findall("testcase/failure")), int(suite.get("failures")), name)
            self.assertEqual(len(suite.findall("testcase/error")), int(suite.get("errors")), name)
            self.assertEqual(len(suite.findall("testcase/skipped")), int(suite.get("skipped")), name)
            self.assertRegex(suite.get("time"), r"^\d+\.\d{3}$", name)
        by_name = {suite.get("name"): suite for suite in suites}

        asserts = by_name["test_asserts.ahk"]
        self.assertEqual([case.get("name") for case in asserts.findall("testcase")],
                         ["one is one", "one is two", "truthy", "needs a screen"])
        self.assertEqual(asserts.find("testcase[@name='one is one']").get("classname"), "test_asserts.ahk")
        failure = asserts.find("testcase[@name='one is two']/failure")
        self.assertEqual(failure.get("message"), "expected: 2  actual: 1")
        self.assertRegex(failure.text, r"test_asserts\.ahk:3$")
        self.assertIsNotNone(asserts.find("testcase[@name='needs a screen']/skipped"))

        error = by_name["test_crash.ahk"].find("testcase/error")
        self.assertIn("no summary line", error.get("message"))
        self.assertIn("boom", error.text)

        summary_only = by_name["test_summary_only.ahk"]
        self.assertEqual(int(summary_only.get("tests")), 3)
        self.assertEqual(int(summary_only.get("failures")), 2)

    def test_junit_write_failure_keeps_exit_code(self):
        self.fixture("pass", 'Print("qa: 1 passed, 0 failed")\nExitApp(0)')
        blocker = Path(self.temp.name) / "blocker"
        blocker.write_text("not a directory")
        code, output = self.run_suite(junit=blocker / "qa.xml")
        self.assertEqual(code, 0, output)
        self.assertIn("JUnit report", output)
        self.assertIn("not written", output)
        self.assertIn("[PASS] test_pass.ahk", output)

    def test_junit_not_written_without_env(self):
        self.fixture("pass", 'Print("qa: 1 passed, 0 failed")\nExitApp(0)')
        report = Path(self.temp.name) / "qa.xml"
        code, output = self.run_suite()
        self.assertEqual(code, 0, output)
        self.assertFalse(report.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
