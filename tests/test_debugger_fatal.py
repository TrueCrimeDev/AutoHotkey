"""A refused or lost DBGp socket must not prompt in unattended runs. Usage: python tests/test_debugger_fatal.py ENGINE

Under /Headless or /ErrorStdOut, SocketTransport::Connect opened a modal
Abort/Retry/Ignore box when nothing listened on the /Debug port, and
Debugger::FatalError opened a Yes/No "Continue running the script without the
debugger?" box when the client vanished. The engine must instead print one
notice on stderr (one JSON warning record under /Diag=json) and finish the
script without the debugger.

An engine without the fix puts those dialogs on the desktop until the deadline
kills it. So before anything is spawned, the engine file is searched for the
fixed notice text; when it is missing the suite prints why and exits SKIPPED,
which tests/run_console_gate.py reports as a skip. The lost-connection cases
listen on a free loopback port, let the engine connect, read its init packet
and reset the connection; the refused case points /Debug at a port that was
bound and closed just before.
"""
import json
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
DEADLINE = 20  # Seconds. A clean run takes a few; a prompt waits forever.
SKIPPED = 77  # Exit status for "not run" (the automake convention), read by run_console_gate.py.
# The notice formats in Debugger.cpp. Only an engine with the fix holds them (UTF-16LE literals).
NOTICES = {"connect": "Could not connect to %s; continuing without the debugger.",
           "lost": "Connection to %s lost; continuing without the debugger."}


def missing_fix(engine):
    """Return why ENGINE must not be spawned here, or None. Reads the file; never runs it."""
    try:
        image = engine.read_bytes()
    except OSError as error:
        return f"it cannot be read ({error})"
    missing = [text for text in NOTICES.values() if text.encode("utf-16-le") not in image]
    if missing:
        return "it lacks the notice text " + " and ".join(repr(text) for text in missing)
    return None


REASON = missing_fix(ENGINE)
if REASON:
    print(f"SKIP: {Path(__file__).name} did not run {ENGINE}: {REASON}. Without the fix the "
          "engine shows modal debugger dialogs on the desktop, so it is not spawned.", flush=True)
    raise SystemExit(SKIPPED)


def notice(kind, port):
    return NOTICES[kind].replace("%s", f"localhost:{port}")


def plain_notice(kind, port):
    return f"Debugger error: {notice(kind, port)}".encode("ascii")


def closed_port():
    """A loopback port that was free a moment ago: bound, then closed, so nothing listens."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        probe.bind(("127.0.0.1", 0))  # A free port, never a fixed one such as 9000.
        return probe.getsockname()[1]
    finally:
        probe.close()


class SocketSession:
    def __init__(self, script, *options):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))  # A free port, never a fixed one such as 9000.
        self.listener.listen(1)
        self.listener.settimeout(DEADLINE)
        self.port = self.listener.getsockname()[1]
        self.connection = None
        self.received = b""
        self.process = subprocess.Popen(
            [str(ENGINE), *options, f"/Debug=localhost:{self.port}", str(script)],
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

    def write(self, name, source):
        script = self.root / name
        script.write_text(source, encoding="utf-8")
        return script

    def start(self, name, source, *options):
        session = SocketSession(self.write(name, source), *options)
        self.addCleanup(session.close)
        try:
            session.accept()
            self.assertTrue(session.packet().tag.endswith("init"))
        except BaseException:
            session.close()  # Do not leave a stuck engine running into the next case.
            raise
        return session

    def run_refused(self, name, *options):
        port = closed_port()
        command = [str(ENGINE), *options, f"/Debug=localhost:{port}",
                   str(self.write(name, 'Print("after-connect")\n'))]
        try:
            # run() kills the child when the deadline passes.
            result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                                    timeout=DEADLINE, creationflags=CREATE_NO_WINDOW)
        except subprocess.TimeoutExpired:
            raise AssertionError(f"Engine still running {DEADLINE} seconds after its debugger "
                                 "connection was refused (a modal prompt blocks here)") from None
        return port, result

    def assert_notice(self, errors, kind, port, options):
        if "/Diag=json" not in options:
            self.assertEqual(errors.splitlines(), [plain_notice(kind, port)])
            return
        lines = errors.splitlines()
        self.assertEqual(len(lines), 1, errors)
        try:
            record = json.loads(lines[0])
        except ValueError:
            raise AssertionError(f"stderr is not one JSON record under /Diag=json: {errors!r}") from None
        self.assertEqual(record, {
            "kind": "diagnostic", "format": "json", "schema": 2, "severity": "warning",
            "type": "Warning", "code": 0, "message": notice(kind, port), "extra": f"localhost:{port}",
            "what": "Debugger", "file": "", "line": 0, "column": 0, "source": "", "stack": ""})

    def test_refused_connection_continues_without_debugger(self):
        # Nothing listens on the port: no Abort/Retry/Ignore box, the script runs on.
        mirror = self.root / "stderr.txt"
        cases = (["/Headless", f"/StdErrFile={mirror}"], ["/ErrorStdOut"], ["/Headless", "/Diag=json"])
        for index, options in enumerate(cases):
            with self.subTest(options=options):
                port, result = self.run_refused(f"refused_{index}.ahk", *options)
                self.assert_notice(result.stderr, "connect", port, options)
                self.assertEqual(result.stdout.splitlines(), [b"after-connect"], result.stderr)
                self.assertEqual(result.returncode, 0, result.stderr)
                if f"/StdErrFile={mirror}" in options:  # Mirrored like other diagnostics.
                    self.assertTrue(mirror.is_file(), "/StdErrFile received nothing")
                    self.assertEqual(mirror.read_bytes(), result.stderr)

    def test_reset_at_first_break_continues_without_debugger(self):
        # Connect() breaks before the first line, so this is the receive in that break.
        cases = (["/Headless"], ["/ErrorStdOut"], ["/Headless", "/Diag=json"])
        for index, options in enumerate(cases):
            with self.subTest(options=options):
                session = self.start(f"first_break_{index}.ahk",
                                     'Sleep(500)\nPrint("after-reset")\n', *options)
                session.reset()
                code, output, errors = session.finish()
                self.assert_notice(errors, "lost", session.port, options)
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
        session.wait_for_stderr(plain_notice("lost", session.port))
        self.assertIsNone(session.process.poll())  # The notice does not end the script.
        code, output, errors = session.finish()
        self.assertEqual(errors.splitlines(), [b"running", plain_notice("lost", session.port)])
        self.assertEqual(output.splitlines(), [b"after-reset"], errors)
        self.assertEqual(code, 0, errors)


if __name__ == "__main__":
    unittest.main()
