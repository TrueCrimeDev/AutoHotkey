"""Console runtime boundary regressions. Usage: python tests/test_runtime_regressions.py ENGINE"""
import base64
import json
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET


ENGINE = Path(sys.argv.pop(1)).resolve()
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def packets(data):
    result = []
    while data:
        header, separator, rest = data.partition(b"\0")
        if not separator or not header.isdigit():
            raise AssertionError(f"Invalid DBGp length header: {header[:80]!r}")
        size = int(header)
        if len(rest) <= size or rest[size] != 0:
            raise AssertionError("Incomplete DBGp packet")
        result.append(ET.fromstring(rest[:size]))
        data = rest[size + 1:]
    return result


class DebugSession:
    def __init__(self, script):
        self.process = subprocess.Popen(
            [str(ENGINE), "/Headless", "/Debug=stdio", str(script)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=CREATE_NO_WINDOW)
        self.output = queue.Queue()
        self.errors = queue.Queue()
        self.threads = [threading.Thread(target=self.read_output, daemon=True),
                        threading.Thread(target=self.read_errors, daemon=True)]
        for thread in self.threads:
            thread.start()

    def read_output(self):
        while True:
            value = self.process.stdout.read(1)
            self.output.put(value)
            if not value:
                return

    def read_errors(self):
        for value in self.process.stderr:
            self.errors.put(value)

    def packet(self):
        header = bytearray()
        while True:
            value = self.output.get(timeout=3)
            if value == b"\0":
                break
            if not value:
                raise AssertionError("Debugger stream closed before a packet")
            header.extend(value)
        if not header.isdigit():
            raise AssertionError(f"Invalid DBGp length header: {header!r}")
        body = b"".join(self.output.get(timeout=3) for _ in range(int(header)))
        if self.output.get(timeout=3) != b"\0":
            raise AssertionError("Missing DBGp packet terminator")
        return ET.fromstring(body)

    def send(self, command):
        self.process.stdin.write(command.encode("ascii") + b"\0")
        self.process.stdin.flush()

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=3)
        for thread in self.threads:
            thread.join(timeout=3)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


class RuntimeRegressions(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="ahk-runtime-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)

    def script(self, source, name="sample.ahk"):
        path = self.root / name
        path.write_text(source, encoding="utf-8")
        return path

    def run_script(self, source, *options, stdin=None):
        return subprocess.run([str(ENGINE), "/Headless", *options, str(self.script(source))],
                              input=stdin, capture_output=True, timeout=10,
                              creationflags=CREATE_NO_WINDOW)

    def test_print_and_console_views_use_debugger_stream_packets(self):
        result = self.run_script('Print("hello 日本語")\nListVars()\n',
                                 "/Debug=stdio", stdin=b"run -i 1\0")
        self.assertEqual(result.returncode, 0, result.stderr)
        messages = packets(result.stdout)
        output = b"".join(base64.b64decode(message.text or "") for message in messages
                          if message.tag.endswith("stream"))
        self.assertIn("hello 日本語\n".encode("utf-8"), output)
        self.assertIn(b"Global Variables", output)
        self.assertEqual(messages[-1].get("status"), "stopped")

    def start_idle_debugger(self):
        session = DebugSession(self.script('Persistent()\nFileAppend("ready`n", "**")\n'))
        self.addCleanup(session.close)
        self.assertTrue(session.packet().tag.endswith("init"))
        session.send("run -i 1")
        self.assertEqual(session.errors.get(timeout=3).strip(), b"ready")
        return session

    def test_idle_debugger_wakes_and_rearms(self):
        session = self.start_idle_debugger()
        for transaction in (2, 3):
            session.send(f"status -i {transaction}")
            reply = session.packet()
            self.assertEqual(reply.get("transaction_id"), str(transaction))
            self.assertEqual(reply.get("status"), "running")
        session.send("stop -i 4")
        self.assertEqual(session.packet().get("status"), "stopped")
        self.assertEqual(session.process.wait(timeout=3), 0)

    def test_idle_debugger_detects_closed_input(self):
        session = self.start_idle_debugger()
        session.process.stdin.close()
        self.assertIn(b"Debugger error:", session.errors.get(timeout=3))
        self.assertIsNone(session.process.poll())  # Detach leaves the persistent script running.

    def test_crash_log_truncates_long_fields_without_crossing_buffers(self):
        log = self.root / "crash.log"
        result = self.run_script('throw Error(Format("{:03000}", 0), "context-marker")\n',
                                 f"/CrashLog={log}")
        self.assertEqual(result.returncode, 10, result.stderr)
        content = log.read_text(encoding="utf-8")
        message = content.split("  Message: ", 1)[1].splitlines()[0]
        self.assertTrue(message)
        self.assertEqual(set(message), {"0"})
        self.assertLessEqual(len(message.encode("utf-8")), 2047)
        self.assertIn("  What: context-marker\n", content)

    def test_crash_log_unicode_truncation_remains_valid_utf8(self):
        log = self.root / "unicode.log"
        source = 'text := ""\nLoop 1500\n    text .= "😀"\nthrow Error(text)\n'
        result = self.run_script(source, f"/CrashLog={log}")
        self.assertEqual(result.returncode, 10, result.stderr)
        message = log.read_text(encoding="utf-8").split("  Message: ", 1)[1].splitlines()[0]
        self.assertTrue(message)
        self.assertEqual(set(message), {"😀"})
        self.assertLessEqual(len(message.encode("utf-8")), 2047)

    def test_oversized_eval_is_catchable_and_does_not_end_the_script(self):
        source = ('#EnableEval\ntry Eval(Format("{:350000}", "") "1+2")\n'
                  'catch ValueError\n    Print("caught")\nPrint(Eval("40+2"))\n')
        result = self.run_script(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [b"caught", b"42"])

    def test_repl_recovers_after_oversized_expression(self):
        result = subprocess.run([str(ENGINE), "/Headless", "/Diag=json", "repl"],
                                input=('"' + 'x' * 17000 + '"\n40+2\n').encode("utf-8"),
                                capture_output=True, timeout=10, creationflags=CREATE_NO_WINDOW)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertFalse(rows[0]["ok"])
        self.assertEqual(rows[0]["type"], "ValueError")
        self.assertEqual(rows[1]["value"], "42")

    def test_eval_exact_limit_and_returned_closure(self):
        source = '''#EnableEval
expression := '"' Format("{:016382}", 1) '"'
Print(StrLen(Eval(expression)))
try Eval('"' Format("{:016383}", 1) '"')
catch ValueError
    Print("over-limit")
MakeAdder(n) {
    add := (x)=>n+x
    return Eval("add")
}
adder := MakeAdder(40)
Print(adder(2))
generated := Eval("(x)=>x+40")
Print(generated(2))
Print(Eval("Eval('6*7')"))
'''
        result = self.run_script(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [b"16382", b"over-limit", b"42", b"42", b"42"])

    def test_eval_functions_do_not_invent_coverage_lines(self):
        report = self.root / "coverage.lcov"
        result = self.run_script('#EnableEval\nx:=1\nf:=Eval("()=>42")\nPrint(f())\n',
                                 f"/Coverage={report}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), b"42")
        lines = [line for line in report.read_text(encoding="utf-8").splitlines()
                 if line.startswith("DA:")]
        self.assertEqual(lines, ["DA:2,1", "DA:3,1", "DA:4,1"])

    def test_coverage_snapshot_includes_loaded_module_functions(self):
        self.script('#Module Lib\nLoaded() {\n    return 7\n}\n'
                    'Unused() {\n    return 0\n}\n#Module __Main\n', "helper.ahk")
        report = self.root / "modules.lcov"
        result = self.run_script('#Include helper.ahk\n#Import Lib {Loaded}\nPrint(Loaded())\n',
                                 f"/Coverage={report}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), b"7")
        records = {}
        current = None
        for line in report.read_text(encoding="utf-8").splitlines():
            if line.startswith("SF:"):
                current = records.setdefault(Path(line[3:]).name, [])
            elif line.startswith("DA:"):
                current.append(line)
        self.assertEqual(records["sample.ahk"], ["DA:3,1"])
        self.assertEqual(records["helper.ahk"], ["DA:3,1", "DA:6,0"])

    def test_check_shared_child_preserves_results_and_never_runs_the_body(self):
        marker = self.root / "executed.txt"
        source = f'''sentinel := 42
valid := Check('#DllLoad kernel32.dll`nFileAppend("executed", "{marker}")')
invalid := Check("x := (`n")
Print(JSON.Stringify({{ok:valid.Ok, validDiagnostics:valid.Diagnostics.Length,
    invalid:invalid.Ok, severity:invalid.Diagnostics[1].Severity,
    message:invalid.Diagnostics[1].Message, line:invalid.Diagnostics[1].Line,
    hasRaw:StrLen(invalid.Raw)>0, sentinel:sentinel}}))
'''
        result = self.run_script(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        self.assertEqual(record["ok"], 1)
        self.assertEqual(record["validDiagnostics"], 0)
        self.assertEqual(record["invalid"], 0)
        self.assertEqual(record["severity"], "error")
        self.assertTrue(record["message"])
        self.assertGreater(record["line"], 0)
        self.assertTrue(record["hasRaw"])
        self.assertEqual(record["sentinel"], 42)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
