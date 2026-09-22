"""Bounded native process/MCP regressions (Windows, Python standard library).

Usage: python tests/test_process_mcp_regressions.py path/to/AutoHotkey64Console.exe
Every spawned script is confined to temporary fixtures and has an outer timeout.
"""
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


EXE = Path(sys.argv.pop(1) if len(sys.argv) > 1 and not sys.argv[1].startswith("-")
           else "bin/AutoHotkey64Console.exe").resolve()
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class ProcessMcpRegressions(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="ahk-process-mcp-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def script(self, name, source):
        path = self.root / name
        path.write_text(source, encoding="utf-8")
        return path

    def ahk(self, source, *args):
        path = self.script("parent.ahk", source)
        result = subprocess.run([str(EXE), "/Headless", "/ErrorStdOut", str(path), *map(str, args)],
                                capture_output=True, text=True, encoding="utf-8", timeout=10,
                                creationflags=NO_WINDOW)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout.splitlines()

    def exchange(self, *requests, cwd=None):
        result = subprocess.run([str(EXE), "mcp"],
                                input="".join(json.dumps(req) + "\n" for req in requests),
                                capture_output=True, text=True, encoding="utf-8", timeout=12,
                                creationflags=NO_WINDOW, cwd=cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return [json.loads(line) for line in result.stdout.splitlines()]

    @staticmethod
    def request(tool, arguments):
        return {"jsonrpc": "2.0", "id": "tool", "method": "tools/call",
                "params": {"name": tool, "arguments": arguments}}

    def call(self, tool, **arguments):
        response, = self.exchange(self.request(tool, arguments))
        self.assertNotIn("error", response, response)
        return json.loads(response["result"]["content"][0]["text"])

    def test_exit_259_is_a_completed_process(self):
        child = self.script("exit.ahk", "ExitApp(259)\n")
        lines = self.ahk('''
p := ProcessPipe(A_AhkPath, ["/Headless", "/ErrorStdOut", A_Args[1]])
try {
    code := p.Wait(1)
    Print("{}:{}:{}", code, p.Running, p.ExitCode)
} catch TimeoutError {
    Print("timeout")
} finally {
    p.Kill()
}
''', child)
        self.assertEqual(lines, ["259:0:259"])
        result = self.call("run", file=str(child), timeout_ms=200)
        self.assertEqual((result["exitCode"], result["timedOut"]), (259, False))

    def test_kill_stops_descendants_after_launcher_exits(self):
        sleeper = self.script("sleeper.ahk", "Sleep(5000)\n")
        launcher = self.script("launcher.ahk", '''
Run('"' A_AhkPath '" /Headless "' A_Args[1] '"', , "Hide", &childPid)
Print(childPid)
''')
        lines = self.ahk('''
p := ProcessPipe(A_AhkPath, ["/Headless", "/ErrorStdOut", A_Args[1], A_Args[2]])
try {
    childPid := Integer(p.ReadLine(2))
    Print("parent:{}", p.Wait(2))
    p.Kill()
    Loop 100 {
        if !ProcessExist(childPid)
            break
        Sleep(10)
    }
    Print("descendant:{}", !!ProcessExist(childPid))
} finally {
    p := ""
}
''', launcher, sleeper)
        self.assertEqual(lines, ["parent:0", "descendant:0"])

    def test_busy_pipe_yields_to_wait_timeout(self):
        child = self.script("flood.ahk", '''
chunk := Buffer(32 * 1024 * 1024, 120)
outHandle := DllCall("GetStdHandle", "Int", -11, "Ptr")
DllCall("WriteFile", "Ptr", outHandle, "Ptr", chunk, "UInt", chunk.Size, "UInt*", &written := 0, "Ptr", 0)
''')
        lines = self.ahk('''
p := ProcessPipe(A_AhkPath, ["/Headless", "/ErrorStdOut", A_Args[1]])
Sleep(100)
try {
    p.Wait(0.001)
    Print("finished")
} catch TimeoutError {
    Print("timeout")
} finally {
    p.Kill()
}
Print("captured:{}", StrLen(p.Read()))
''', child)
        self.assertEqual(lines[0], "timeout")
        self.assertLess(int(lines[1].split(":")[1]), 32 * 1024 * 1024)

    def test_unrelated_inheritable_handles_are_not_inherited(self):
        child = self.script("event.ahk", 'DllCall("SetEvent", "Ptr", Integer(A_Args[1]))\n')
        lines = self.ahk('''
sa := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
NumPut("UInt", sa.Size, sa)
NumPut("Int", 1, sa, A_PtrSize * 2)
event := DllCall("CreateEventW", "Ptr", sa, "Int", 1, "Int", 0, "Ptr", 0, "Ptr")
if !event
    throw OSError()
try {
    p := ProcessPipe(A_AhkPath, ["/Headless", "/ErrorStdOut", A_Args[1], event])
    p.Wait(2)
    Print(DllCall("WaitForSingleObject", "Ptr", event, "UInt", 0, "UInt"))
} finally {
    DllCall("CloseHandle", "Ptr", event)
}
''', child)
        self.assertEqual(lines, ["258"])

    def test_mcp_capture_limit_is_explicit_and_session_survives(self):
        child = self.script("capture.ahk", '''
chunk := Buffer(65536, 120)
outHandle := DllCall("GetStdHandle", "Int", -11, "Ptr")
Loop 145
    DllCall("WriteFile", "Ptr", outHandle, "Ptr", chunk, "UInt", chunk.Size, "UInt*", &written := 0, "Ptr", 0)
''')
        response, ping = self.exchange(self.request("run", {"file": str(child), "timeout_ms": 5000}),
                                       {"jsonrpc": "2.0", "id": "after", "method": "ping"})
        self.assertNotIn("error", response, response)
        result = json.loads(response["result"]["content"][0]["text"])
        self.assertTrue(result.get("outputLimitExceeded"), result.keys())
        self.assertEqual(result.get("captureLimitBytes"), 8 * 1024 * 1024)
        self.assertLessEqual(len(result["stdout"].encode("utf-8")) + len(result["stderr"].encode("utf-8")),
                             result["captureLimitBytes"])
        self.assertFalse(result["ok"])
        self.assertFalse(result["timedOut"])
        self.assertEqual(ping, {"jsonrpc": "2.0", "id": "after", "result": {}})

    def test_option_shaped_file_is_checked_as_a_file(self):
        self.script("--version", "value := (\n")
        result = self.call("check", file="--version", cwd=str(self.root))
        self.assertEqual((result["ok"], result["exitCode"]), (False, 13))
        self.assertTrue(result["diagnostics"])

    def test_context_radius_saturates_without_integer_overflow(self):
        path = self.script("context.ahk", "first\nsecond")
        result = self.call("get_source_context", file=str(path), line=1, radius=9223372036854775807)
        self.assertEqual([line["text"] for line in result["context"]], ["first", "second"])
        result = self.call("get_source_context", file=str(path), line=9223372036854775807,
                           radius=9223372036854775807)
        self.assertEqual(len(result["context"]), 2)

    def test_context_rejects_negative_and_out_of_range_numbers(self):
        path = self.script("context.ahk", "first\nsecond")
        for argument, value in (("line", 0), ("line", -1), ("radius", -1),
                                ("radius", 9223372036854775808), ("radius", "0x10000000000000000"),
                                ("radius", "1e309"), ("radius", "1\0ignored")):
            with self.subTest(argument=argument, value=value):
                args = {"file": str(path), "line": 1, argument: value}
                response, = self.exchange(self.request("get_source_context", args))
                self.assertIn("error", response)

    def test_string_request_ids_preserve_utf16_surrogates(self):
        for request_id in ("\ud800", "\udfff", "\ud800X\udc00", "\U0001f30d"):
            with self.subTest(request_id=repr(request_id)):
                response, = self.exchange({"jsonrpc": "2.0", "id": request_id, "method": "ping"})
                self.assertEqual(response["id"], request_id)

    def test_workspace_preserves_drive_root(self):
        # A temporary DOS-device mapping gives the test its own drive root. No
        # real system drive is scanned and no files are created outside fixtures.
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.DefineDosDeviceW.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR]
        kernel.DefineDosDeviceW.restype = wintypes.BOOL
        drives = kernel.GetLogicalDrives()
        letter = next((chr(65 + n) for n in range(25, 3, -1) if not drives & (1 << n)), None)
        if letter is None:
            self.skipTest("No unused drive letter for temporary fixture")
        drive = letter + ":"
        target = "\\??\\" + str(self.root)
        if not kernel.DefineDosDeviceW(1 | 8, drive, target):
            self.skipTest(f"Temporary DOS-device mapping unavailable: {ctypes.get_last_error()}")
        self.addCleanup(lambda: kernel.DefineDosDeviceW(1 | 2 | 4 | 8, drive, target))
        self.script("root.ahk", "AtDriveRoot() {\n}\n")
        (self.root / "nested").mkdir()
        (self.root / "nested" / "nested.ahk").write_text("InsideNested() {\n}\n", encoding="utf-8")
        response, = self.exchange(self.request("workspace_symbols", {"root": drive + "\\", "max_results": 1}),
                                  cwd=drive + "\\nested")
        self.assertNotIn("error", response, response)
        result = json.loads(response["result"]["content"][0]["text"])
        self.assertEqual(result["symbols"][0]["name"], "AtDriveRoot")


if __name__ == "__main__":
    unittest.main()
