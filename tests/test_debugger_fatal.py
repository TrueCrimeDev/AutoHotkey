"""A lost DBGp socket must not prompt in unattended runs. Usage: python tests/test_debugger_fatal.py ENGINE

Debugger::FatalError opened a modal "Continue running the script without the
debugger?" box under /Headless and /ErrorStdOut; only /Debug=stdio wrote the
notice to stderr and carried on. Each case listens on a free loopback port,
lets the engine connect, reads its init packet and resets the connection. The
engine must print the stdio notice on stderr and finish the script without the
debugger. An engine that prompts blocks instead, so the child is killed at the
deadline; do not point this at an engine without the fix outside CI, because
the prompt appears on the desktop until then.
"""
import os
from pathlib import Path
import queue
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET


ENGINE = Path(sys.argv.pop(1)).resolve()
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
NOTICE = b"Debugger error: An internal error has occurred in the debugger engine."
DEADLINE = 20  # Seconds. A clean run takes about one; a prompt waits forever.


class SocketSession:
    def __init__(self, script, *options):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))  # A free port, never a fixed one such as 9000.
        self.listener.listen(1)
        self.listener.settimeout(DEADLINE)
        port = self.listener.getsockname()[1]
        self.connection = None
        self.received = b""
        self.process = subprocess.Popen(
            [str(ENGINE), *options, f"/Debug=localhost:{port}", str(script)],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=CREATE_NO_WINDOW)
        self.output = []
        self.errors = queue.Queue()
        self.error_lines = []
        self.threads = [threading.Thread(target=self.read_output, daemon=True),
                        threading.Thread(target=self.read_errors, daemon=True)]
        for thread in self.threads:
            thread.start()

    def read_output(self):
        self.output.append(self.process.stdout.read())

    def read_errors(self):
        for line in self.process.stderr:
            self.errors.put(line)

    def accept(self):
        try:
            self.connection, _ = self.listener.accept()
        except socket.timeout:
            raise AssertionError(f"Engine did not connect within {DEADLINE} seconds") from None
        self.connection.settimeout(DEADLINE)

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
            data = self.connection.recv(65536)
            if not data:
                raise AssertionError("Debugger socket closed before a packet")
            self.received += data

    def send(self, command):
        self.connection.sendall(command.encode("ascii") + b"\0")

    def reset(self):
        # Linger 0 makes close() send RST: the client vanished, it did not detach.
        linger = struct.pack("HH" if os.name == "nt" else "ii", 1, 0)
        self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, linger)
        self.connection.close()
        self.connection = None

    def stderr_line(self, timeout=DEADLINE):
        try:
            line = self.errors.get(timeout=timeout)
        except queue.Empty:
            raise AssertionError(f"No stderr line within {timeout} seconds; "
                                 f"stderr so far: {self.error_lines!r}") from None
        self.error_lines.append(line)
        return line

    def wait_for_stderr(self, text):
        while True:
            line = self.stderr_line()
            if text in line:
                return line

    def finish(self):
        try:
            code = self.process.wait(timeout=DEADLINE)
        except subprocess.TimeoutExpired:
            self.close()
            raise AssertionError(f"Engine still running {DEADLINE} seconds after the connection "
                                 "was reset (a modal prompt blocks here)") from None
        for thread in self.threads:
            thread.join(timeout=3)
        while not self.errors.empty():
            self.error_lines.append(self.errors.get())
        return code, b"".join(self.output), b"".join(self.error_lines)

    def close(self):
        # Kill first: closing a live connection is what makes an unfixed engine prompt.
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=10)
        if self.connection:
            self.connection.close()
            self.connection = None
        self.listener.close()
        for thread in self.threads:
            thread.join(timeout=3)
        self.process.stdout.close()
        self.process.stderr.close()


class DebuggerFatalError(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="ahk-debugger-fatal-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)

    def start(self, name, source, *options):
        script = self.root / name
        script.write_text(source, encoding="utf-8")
        session = SocketSession(script, *options)
        self.addCleanup(session.close)
        try:
            session.accept()
            self.assertTrue(session.packet().tag.endswith("init"))
        except BaseException:
            session.close()  # Do not leave a stuck engine running into the next case.
            raise
        return session

    def test_reset_at_first_break_continues_without_debugger(self):
        # Connect() breaks before the first line, so this is the receive in that break.
        for index, options in enumerate((["/Headless"], ["/ErrorStdOut"])):
            with self.subTest(options=options):
                session = self.start(f"first_break_{index}.ahk",
                                     'Sleep(500)\nPrint("after-reset")\n', *options)
                session.reset()
                code, output, errors = session.finish()
                self.assertIn(NOTICE, errors)
                self.assertEqual(output.splitlines(), [b"after-reset"], errors)
                self.assertEqual(code, 0, errors)

    def test_reset_while_running_continues_without_debugger(self):
        # After "run", the loss arrives as FD_CLOSE while the script sleeps.
        session = self.start("running.ahk",
                             'FileAppend("running`n", "**")\nSleep(3000)\nPrint("after-reset")\n',
                             "/Headless")
        session.send("run -i 1")
        session.wait_for_stderr(b"running")
        session.reset()
        session.wait_for_stderr(NOTICE)
        self.assertIsNone(session.process.poll())  # The notice does not end the script.
        code, output, errors = session.finish()
        self.assertEqual(output.splitlines(), [b"after-reset"], errors)
        self.assertEqual(code, 0, errors)


if __name__ == "__main__":
    unittest.main()
