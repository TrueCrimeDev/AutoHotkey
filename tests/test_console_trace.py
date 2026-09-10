"""Trace output behavior. Usage: python tests/test_console_trace.py ENGINE"""
import json
import ctypes
from pathlib import Path
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ENGINE = Path(sys.argv.pop(1)).resolve()


class ConsoleTraceTests(unittest.TestCase):
    def run_script(self, source, *options, trace=True, files=None):
        with tempfile.TemporaryDirectory(prefix="ahk-trace-") as td:
            script = Path(td) / "trace.ahk"
            script.write_text(source, encoding="utf-8-sig")
            for name, text in (files or {}).items():
                Path(td, name).write_text(text, encoding="utf-8-sig")
            result = subprocess.run([str(ENGINE), "/Headless", *(["/Trace"] if trace else []),
                                     *options, str(script)], capture_output=True, timeout=8,
                                    encoding="utf-8", errors="strict",
                                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout, result.stderr

    def trace_commands(self, stderr):
        rows = stderr.splitlines()
        self.assertTrue(rows, "Expected executed commands")
        commands = []
        for row in rows:
            match = re.fullmatch(r"\[trace\] .+:\d+  (\S.*)", row)
            self.assertIsNotNone(match, repr(row))
            commands.append(match[1])
        self.assertFalse(any(command in ("{", "}", ";end") for command in commands))
        return commands

    def test_only_executed_statements_have_readable_text(self):
        out, err = self.run_script('''; comment and blank lines are not commands

value := 40
Loop 2 {
    value += 1
}
if false {
    Print("NEVER_EXECUTED")
}
Print(value)
''')
        self.assertEqual(out.strip(), "42")
        commands = self.trace_commands(err)
        self.assertIn("value := 40", commands)
        self.assertEqual(commands.count("value += 1"), 2)
        self.assertIn("Print(value)", commands)
        self.assertNotIn("NEVER_EXECUTED", err)
        self.assertNotIn("comment and blank", err)

    def test_unicode_and_multiline_strings_stay_on_one_trace_row(self):
        out, err = self.run_script('value := "日本語 😀`n`nnext"\nPrint(StrLen(value))\n')
        self.assertTrue(out.strip().isdigit())
        commands = self.trace_commands(err)
        self.assertIn('value := "日本語 😀`n`nnext"', commands)

    def test_large_command_is_bounded_and_marked_as_truncated(self):
        out, err = self.run_script('value := "' + 'x' * 8000 + '"\nPrint(StrLen(value))\n')
        self.assertEqual(out.strip(), "8000")
        commands = self.trace_commands(err)
        self.assertLess(len(commands[0]), 3000)
        self.assertTrue(commands[0].endswith("..."), commands[0][-30:])

    def test_included_file_is_identified(self):
        out, err = self.run_script('#Include helper.ahk\nPrint(Answer())\n', files={
            "helper.ahk": 'Answer() {\n    return 42\n}\n'})
        self.assertEqual(out.strip(), "42")
        self.trace_commands(err)
        self.assertRegex(err, r"\[trace\] helper\.ahk:2  Return 42")
        self.assertRegex(err, r"\[trace\] trace\.ahk:2  Print\(Answer\(\)\)")

    def test_listlines_toggle_and_disabled_trace_remain_quiet(self):
        source = 'ListLines(false)\nPrint("hidden from trace")\nListLines(true)\nPrint("visible in trace")\n'
        out, err = self.run_script(source)
        self.assertIn("hidden from trace", out)
        self.trace_commands(err)
        self.assertNotIn("hidden from trace", err)
        self.assertIn('Print("visible in trace")', err)
        out, err = self.run_script(source, trace=False)
        self.assertEqual(err, "")

    def test_json_stdout_is_not_polluted_by_trace(self):
        out, err = self.run_script('Print(JSON.Stringify({answer: 42}))\n')
        self.assertEqual(json.loads(out), {"answer": 42})
        self.trace_commands(err)

    def test_idle_is_quiet_and_hotkey_dispatch_traces_its_commands(self):
        # Post only to this fixture's script window; no global keyboard input.
        with tempfile.TemporaryDirectory(prefix="ahk-trace-hotkey-") as td:
            script = Path(td) / "hotkey.ahk"
            script.write_text('''#SingleInstance Off
F24:: {
    Print("hotkey fired")
    ExitApp()
}
Print(A_ScriptHwnd)
''', encoding="utf-8-sig")
            child = subprocess.Popen([str(ENGINE), "/Headless", "/Trace", str(script)],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, encoding="utf-8",
                                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            output, traces = queue.Queue(), queue.Queue()
            def read_stream(stream, target):
                for row in stream:
                    target.put(row)
            readers = [threading.Thread(target=read_stream, args=(stream, target), daemon=True)
                       for stream, target in ((child.stdout, output), (child.stderr, traces))]
            for reader in readers:
                reader.start()
            try:
                hwnd = int(output.get(timeout=4).strip())
                # Let the finite startup sequence finish before measuring idle output.
                time.sleep(0.15)
                startup = []
                while not traces.empty():
                    startup.append(traces.get_nowait())
                self.trace_commands("".join(startup))
                with self.assertRaises(queue.Empty):
                    traces.get(timeout=0.25)
                user32 = ctypes.WinDLL("user32", use_last_error=True)
                user32.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
                owner_pid = ctypes.c_ulong()
                self.assertTrue(user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner_pid)))
                self.assertEqual(owner_pid.value, child.pid)
                user32.PostMessageW.argtypes = [ctypes.c_void_p, ctypes.c_uint,
                                               ctypes.c_size_t, ctypes.c_ssize_t]
                self.assertTrue(user32.PostMessageW(hwnd, 0x0312, 0, 0))  # First hotkey ID.
                self.assertEqual(output.get(timeout=4).strip(), "hotkey fired")
                self.assertEqual(child.wait(timeout=4), 0)
                for reader in readers:
                    reader.join(timeout=1)
                commands = self.trace_commands("".join(traces.queue))
                self.assertIn('Print("hotkey fired")', commands)
                self.assertIn('ExitApp()', commands)
            finally:
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=4)
                for reader in readers:
                    reader.join(timeout=1)
                child.stdout.close()
                child.stderr.close()


if __name__ == "__main__":
    unittest.main()
