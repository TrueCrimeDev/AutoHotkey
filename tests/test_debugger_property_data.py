"""DBGp property_get must return long and non-BMP string values intact. Usage: python tests/test_debugger_property_data.py ENGINE

Debugger::WritePropertyData (source/Debugger.cpp) converts a value to UTF-8 in
the tail of the response buffer and base64-encodes it forward from the write
position. Two defects, both inherited from upstream:

- The UTF-8 sizing loop tested each UTF-16 unit for a surrogate pair without
  skipping the low surrogate, so a pair counted 4 + 3 bytes. The size attribute
  was wrong for any non-BMP character, and a -m limit that landed on a pair
  cut it in half, which WideCharToMultiByte turned into U+FFFD.
- The UTF-8 scratch area sat only as far from the write position as the
  buffer's growth happened to leave, while the encoder writes 4 bytes for
  every 3 it reads. When the buffer grew to just the reserved size, the
  encoded output overtook the unencoded input and the data was corrupted
  for large values (the damage depended on the value's size).

Each case drives the engine over /Debug=stdio: run to a breakpoint after the
values are built, property_get each one, and compare the base64-decoded data
with the same string built here. The sizes are chosen so that the old code's
overlap window is hit (90000 and 180000 bytes land just under a doubling of
the buffer) as well as missed (100000 bytes), so the suite fails on an engine
without the fix and still checks the sizes an IDE would ask for.
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
DEADLINE = 30  # Seconds per packet; a clean case takes well under five.

# The values the script builds, computed here the same way (A_Index is 1-based).
ASCII_90K = "".join(chr(32 + (i % 95)) for i in range(1, 90001))
ASCII_100K = "".join(chr(32 + (i % 95)) for i in range(1, 100001))
ASCII_180K = "".join(chr(32 + (i % 95)) for i in range(1, 180001))
# Odd positions are emoji (surrogate pairs, 4 UTF-8 bytes), even positions CJK (3 bytes).
MIXED_20K = "".join(chr(0x1F600 + (i % 64)) if i % 2 else chr(0x4E00 + (i % 2000))
                    for i in range(1, 20001))
# A short value for the -m cases that land inside and beside a surrogate pair.
SHORT = "a" + "\U0001F600" + "é" + "中" + "\U0001F601"

SCRIPT = """#Requires AutoHotkey v2.0
ascii90k := ""
Loop 90000
    ascii90k .= Chr(32 + Mod(A_Index, 95))
ascii100k := ""
Loop 100000
    ascii100k .= Chr(32 + Mod(A_Index, 95))
ascii180k := ""
Loop 180000
    ascii180k .= Chr(32 + Mod(A_Index, 95))
mixed20k := ""
Loop 20000
    mixed20k .= Mod(A_Index, 2) ? Chr(0x1F600 + Mod(A_Index, 64)) : Chr(0x4E00 + Mod(A_Index, 2000))
short := "a" Chr(0x1F600) Chr(0xE9) Chr(0x4E2D) Chr(0x1F601)
done := 1
"""
BREAK_LINE = SCRIPT.splitlines().index("done := 1") + 1


def utf8_length(text):
    return len(text.encode("utf-8"))


class StdioSession:
    """One engine run under /Debug=stdio: DBGp packets on stdout, commands on stdin."""

    def __init__(self, script):
        self.process = subprocess.Popen(
            [str(ENGINE), "/Headless", "/Debug=stdio", str(script)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=CREATE_NO_WINDOW)
        self.received = b""
        self.chunks = queue.Queue()
        self.errors = []
        self.transaction = 0
        self.threads = [threading.Thread(target=self.read_output, daemon=True),
                        threading.Thread(target=self.read_errors, daemon=True)]
        for thread in self.threads:
            thread.start()

    def read_output(self):
        while True:
            data = os.read(self.process.stdout.fileno(), 65536)
            self.chunks.put(data)
            if not data:
                return

    def read_errors(self):
        self.errors.append(self.process.stderr.read())

    def packet(self):
        while True:
            header, separator, rest = self.received.partition(b"\0")
            if separator:
                if not header.isdigit():
                    raise AssertionError(f"Invalid DBGp length header: {header[:80]!r}")
                size = int(header)
                if len(rest) > size:
                    if rest[size] != 0:
                        raise AssertionError("Missing DBGp packet terminator")
                    self.received = rest[size + 1:]
                    return ET.fromstring(rest[:size])
            try:
                data = self.chunks.get(timeout=DEADLINE)
            except queue.Empty:
                raise AssertionError(f"No DBGp packet within {DEADLINE} seconds; stderr: "
                                     f"{self.stderr()!r}") from None
            if not data:
                raise AssertionError(f"Debugger stdout closed before a packet; stderr: {self.stderr()!r}")
            self.received += data

    def send(self, command):
        self.transaction += 1
        self.process.stdin.write(f"{command} -i {self.transaction}".encode("utf-8") + b"\0")
        self.process.stdin.flush()
        return str(self.transaction)

    def command(self, command):
        transaction = self.send(command)
        response = self.packet()
        if response.tag != "response" or response.get("transaction_id") != transaction:
            raise AssertionError(f"Unexpected packet for {command!r}: {ET.tostring(response)[:200]!r}")
        error = response.find("error")
        if error is not None:
            raise AssertionError(f"{command!r} failed: {ET.tostring(error)!r}")
        return response

    def stderr(self):
        return b"".join(self.errors)

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=10)
        for thread in self.threads:
            thread.join(timeout=3)
        self.process.stdin.close()
        self.process.stdout.close()
        self.process.stderr.close()


class DebuggerPropertyData(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="ahk-debugger-property-")
        self.addCleanup(self.folder.cleanup)
        self.script = Path(self.folder.name) / "values.ahk"
        self.script.write_text(SCRIPT, encoding="utf-8")

    def start(self):
        """Start the engine and run the script to the breakpoint after the values are built."""
        session = StdioSession(self.script)
        self.addCleanup(session.close)
        self.assertEqual(session.packet().tag, "init")
        session.command(f"breakpoint_set -t line -n {BREAK_LINE}")
        response = session.command("run")
        self.assertEqual(response.get("status"), "break", ET.tostring(response))
        return session

    def property_get(self, session, name, max_data):
        """Return (size attribute, decoded UTF-8 bytes) of a string variable."""
        response = session.command(f"property_get -n {name} -m {max_data}")
        prop = response.find("property")
        self.assertIsNotNone(prop, ET.tostring(response)[:300])
        self.assertEqual(prop.get("type"), "string", ET.tostring(prop)[:300])
        self.assertEqual(prop.get("encoding"), "base64", ET.tostring(prop)[:300])
        data = base64.b64decode(prop.text or "", validate=True)
        return int(prop.get("size")), data

    def assert_whole(self, session, name, expected):
        size, data = self.property_get(session, name, 0)  # -m 0 means unlimited.
        self.assertEqual(size, utf8_length(expected), f"{name}: size attribute")
        self.assertEqual(len(data), utf8_length(expected), f"{name}: data length")
        if data != expected.encode("utf-8"):
            first = next(index for index, (a, b) in enumerate(zip(data, expected.encode("utf-8")))
                         if a != b)
            self.fail(f"{name}: data differs from the value from byte {first} of {len(data)}")

    def assert_truncated(self, session, name, expected, max_data):
        """A limited read keeps the full size and sends the longest whole-character prefix."""
        size, data = self.property_get(session, name, max_data)
        self.assertEqual(size, utf8_length(expected), f"{name} -m {max_data}: size attribute")
        self.assertLessEqual(len(data), max_data, f"{name} -m {max_data}: over the limit")
        text = data.decode("utf-8")  # Strict: a split pair would decode to U+FFFD or fail.
        self.assertTrue(expected.startswith(text), f"{name} -m {max_data}: not a prefix")
        if text != expected:  # The next character must be the one that did not fit.
            self.assertGreater(len(data) + utf8_length(expected[len(text)]), max_data,
                               f"{name} -m {max_data}: a whole character was left out")
        return text

    def test_ascii_values_arrive_intact(self):
        session = self.start()
        self.assert_truncated(session, "ascii90k", ASCII_90K, 1000)
        for name, expected in (("ascii90k", ASCII_90K), ("ascii100k", ASCII_100K),
                               ("ascii180k", ASCII_180K)):
            with self.subTest(name=name):
                self.assert_whole(session, name, expected)

    def test_mixed_value_size_and_data(self):
        session = self.start()
        self.assert_truncated(session, "mixed20k", MIXED_20K, 5000)
        self.assert_whole(session, "mixed20k", MIXED_20K)

    def test_limit_never_splits_a_surrogate_pair(self):
        session = self.start()
        # "a" (1) + emoji (4) + e-acute (2) + CJK (3) + emoji (4) = 14 bytes.
        self.assertEqual(utf8_length(SHORT), 14)
        expectations = {1: "a", 2: "a", 4: "a", 5: "a\U0001F600", 6: "a\U0001F600",
                        7: "a\U0001F600é", 9: "a\U0001F600é", 10: "a\U0001F600é中",
                        13: "a\U0001F600é中", 14: SHORT, 100: SHORT}
        for max_data, expected in expectations.items():
            with self.subTest(max_data=max_data):
                text = self.assert_truncated(session, "short", SHORT, max_data)
                self.assertEqual(text, expected)
        self.assert_whole(session, "short", SHORT)

    def test_session_ends_cleanly(self):
        session = self.start()
        self.assert_whole(session, "short", SHORT)
        response = session.command("detach")
        self.assertEqual(response.get("status"), "stopped", ET.tostring(response))
        self.assertEqual(session.process.wait(timeout=DEADLINE), 0, session.stderr())


if __name__ == "__main__":
    unittest.main()
