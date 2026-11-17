"""DBGp eval evaluates an expression in the paused function's scope. Usage: python tests/test_debugger_eval.py ENGINE

Upstream AutoHotkey has no DBGp eval command (it answers error 4), so clients
could only read variable and property paths with property_get. The fork's
Debugger::eval (source/Debugger.cpp) runs the expression through the same
ConsoleEval::Evaluate as the Eval BIF, in the scope of the function the script
is paused in, and answers with one <property> as property_get would. A syntax
error or a thrown exception answers error 206 with the exception's message.

Each case drives the engine over /Debug=stdio to a breakpoint inside a function.
"""
import base64
import os
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
DEADLINE = 15  # Seconds per packet.

SCRIPT = """g := 10
F(a) {
    b := a * 2
    return b
}
Print(F(21))
"""
BREAK_LINE = 4  # return b: a is 21 and b is 42.


class StdioSession:
    def __init__(self, script):
        self.process = subprocess.Popen(
            [str(ENGINE), "/Headless", "/Debug=stdio", str(script)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=CREATE_NO_WINDOW)
        self.received = b""
        self.chunks = queue.Queue()
        self.transaction = 0
        self.reader = threading.Thread(target=self.read_output, daemon=True)
        self.reader.start()

    def read_output(self):
        while True:
            data = os.read(self.process.stdout.fileno(), 65536)
            self.chunks.put(data)
            if not data:
                return

    def packet(self):
        while True:
            header, separator, rest = self.received.partition(b"\0")
            if separator and header.isdigit() and len(rest) > int(header):
                self.received = rest[int(header) + 1:]
                return ET.fromstring(rest[:int(header)])
            try:
                data = self.chunks.get(timeout=DEADLINE)
            except queue.Empty:
                raise AssertionError(f"No DBGp packet within {DEADLINE} seconds") from None
            if not data:
                raise AssertionError("Debugger stdout closed before a packet")
            self.received += data

    def command(self, command, data=None):
        self.transaction += 1
        text = f"{command} -i {self.transaction}"
        if data is not None:
            text += " -- " + base64.b64encode(data.encode("utf-8")).decode("ascii")
        self.process.stdin.write(text.encode("utf-8") + b"\0")
        self.process.stdin.flush()
        response = self.packet()
        if response.tag == "stream" and command == "run":
            return response
        if response.tag != "response" or response.get("transaction_id") != str(self.transaction):
            raise AssertionError(f"Unexpected packet for {command!r}: {ET.tostring(response)[:200]!r}")
        return response

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=10)
        self.reader.join(timeout=3)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


def decoded(prop):
    return base64.b64decode(prop.text or "").decode("utf-8")


class DebuggerEval(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="ahk-debugger-eval-")
        self.addCleanup(folder.cleanup)
        script = Path(folder.name) / "eval.ahk"
        script.write_text(SCRIPT, encoding="utf-8")
        self.session = StdioSession(script)
        self.addCleanup(self.session.close)
        self.assertEqual(self.session.packet().tag, "init")
        self.session.command(f"breakpoint_set -t line -n {BREAK_LINE}")
        response = self.session.command("run")
        self.assertEqual(response.get("status"), "break", ET.tostring(response))

    def eval(self, expression):
        response = self.session.command("eval", expression)
        self.assertEqual(response.get("command"), "eval", ET.tostring(response))
        return response

    def eval_value(self, expression):
        response = self.eval(expression)
        self.assertIsNone(response.find("error"), ET.tostring(response))
        self.assertEqual(response.get("success"), "1", ET.tostring(response))
        prop = response.find("property")
        self.assertIsNotNone(prop, ET.tostring(response))
        return prop

    def test_feature_get_lists_eval(self):
        self.assertEqual(self.session.command("feature_get -n eval").get("supported"), "1")

    def test_expression_over_locals_and_globals(self):
        prop = self.eval_value("a + b + g")
        self.assertEqual((prop.get("type"), decoded(prop)), ("integer", "73"))
        prop = self.eval_value('Format("{}-{}", a, StrLen("abc"))')
        self.assertEqual((prop.get("type"), decoded(prop)), ("string", "21-3"))

    def test_object_result_lists_its_children(self):
        prop = self.eval_value("[a, b]")
        self.assertEqual(prop.get("type"), "object")
        self.assertEqual(prop.get("classname"), "Array")
        self.assertEqual(prop.get("children"), "1")
        items = {child.get("name"): decoded(child) for child in prop.findall("property")}
        self.assertEqual((items.get("[1]"), items.get("[2]")), ("21", "42"), items)

    def test_failures_answer_206_with_the_message(self):
        for expression, message in (("a +", None), ("[1][5]", "Invalid index."),
                                    ("NoSuchVar.Prop", None)):
            response = self.eval(expression)
            self.assertEqual(response.get("success"), "0", ET.tostring(response))
            error = response.find("error")
            self.assertIsNotNone(error, ET.tostring(response))
            self.assertEqual(error.get("code"), "206")
            text = error.findtext("message")
            self.assertTrue(text, ET.tostring(response))
            if message:
                self.assertEqual(text, message)
        # The script is still paused and usable after failures.
        self.assertEqual(decoded(self.eval_value("b")), "42")

    def test_script_finishes_normally_after_eval(self):
        self.eval_value("b")
        response = self.session.command("run")
        while response.tag == "stream":  # Print(F(21)) arrives as a stdout stream packet.
            self.assertIn(b"42\n", base64.b64decode(response.text))
            response = self.session.packet()
        self.assertEqual(response.get("status"), "stopped", ET.tostring(response))
        self.assertEqual(self.session.process.wait(timeout=DEADLINE), 0)


if __name__ == "__main__":
    unittest.main()
