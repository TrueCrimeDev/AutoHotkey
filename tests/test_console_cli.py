"""Console CLI regressions. Usage: python tests/test_console_cli.py [AutoHotkey.exe]."""
import ctypes
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

EXE = Path(sys.argv.pop(1) if len(sys.argv) > 1 and not sys.argv[1].startswith("-")
           else "bin/AutoHotkey64.exe").resolve()


class ConsoleCliTests(unittest.TestCase):
    def run_cli(self, *args, stdin="", cwd=None):
        return subprocess.run([str(EXE), *map(str, args)], input=stdin,
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=8, cwd=cwd,
                              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def test_help_exits_without_loading_a_script(self):
        r = self.run_cli("--help")
        self.assertEqual(r.returncode, 0, r.stderr)
        for word in ("Usage:", "check", "test", "repl", "mcp", "--version", "--capabilities"):
            self.assertIn(word, r.stdout)
        self.assertEqual(r.stderr, "")

    def test_version_reports_build_identity(self):
        r = self.run_cli("--version")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("2.1-alpha.31", r.stdout)
        for word in ("revision=", "compiler=", "architecture="):
            self.assertIn(word, r.stdout)

    def test_help_aliases_and_explicit_run(self):
        for alias in ("help", "-h", "--h", "-help"):
            r = self.run_cli(alias)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("Usage:", r.stdout)
        for args in (("run",), ("run", "/Headless"), ("/Headless", "run"),
                     ("run", ""), ("run", "--", ""), ("--", "")):
            r = self.run_cli(*args)
            self.assertEqual(r.returncode, 64, r.stderr)
            self.assertIn("script filename", r.stderr)
        with tempfile.TemporaryDirectory(prefix="ahk-run-") as td:
            script = Path(td) / "args.ahk"
            script.write_text('for arg in A_Args\n    Print(arg)\n', encoding="utf-8")
            r = self.run_cli("/Headless", "run", script, "--help", "two words", "")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.splitlines(), ["--help", "two words", ""])

    def test_capabilities_are_machine_readable(self):
        r = self.run_cli("--capabilities")
        self.assertEqual(r.returncode, 0, r.stderr)
        info = json.loads(r.stdout)
        self.assertEqual(info["kind"], "capabilities")
        self.assertEqual(info["schema"], 1)
        self.assertIn("2.1-alpha.31", info["version"])
        self.assertRegex(info["build"]["revision"], r"^(?:[0-9a-f]{7,40}(?:-dirty)?|unknown)$")
        self.assertTrue(info["build"]["compiler"])
        self.assertIn(info["build"]["architecture"], ("x64", "x86", "arm64"))
        self.assertTrue({"check", "test", "repl", "mcp"} <= set(info["commands"]))
        self.assertEqual(info["mcp"]["protocolVersions"], ["2025-06-18", "2024-11-05"])
        self.assertEqual(r.stderr, "")

    def test_usage_errors_are_actionable(self):
        for args, hint in ((["check"], "script"), (["--diag=bad"], "diag"),
                           (["--unknown"], "unknown"), (["/include"], "include"),
                           (["/CrashLog="], "CrashLog"), (["/ErrorStdOut=bad"], "encoding")):
            with self.subTest(args=args):
                r = self.run_cli(*args)
                self.assertEqual(r.returncode, 64, r.stderr)
                self.assertIn(hint.lower(), r.stderr.lower())
                self.assertIn("--help", r.stderr)
                self.assertEqual(r.stdout, "")

    def test_flags_before_verb_and_script_arguments(self):
        with tempfile.TemporaryDirectory(prefix="ahk-cli-") as td:
            script = Path(td) / "args.ahk"
            script.write_text('for arg in A_Args\n    Print(arg)\n', encoding="utf-8")
            r = self.run_cli("/Headless", "/Diag=json", "check", script)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(json.loads(r.stdout)["status"], "pass")
            r = self.run_cli("/Headless", script, "--help", "check", "--version")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.splitlines(), ["--help", "check", "--version"])
        r = self.run_cli("/Headless", "repl", "/Diag=json", stdin="6*7\n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["value"], "42")

    def test_end_of_options_allows_command_named_script(self):
        with tempfile.TemporaryDirectory(prefix="ahk-cli-") as td:
            Path(td, "check").write_text('Print("script")\n', encoding="utf-8")
            r = self.run_cli("/Headless", "--", "check", cwd=td)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.strip(), "script")

    @unittest.skipUnless(os.name == "nt", "Windows version resources")
    def test_numeric_file_version_matches_alpha31(self):
        version = ctypes.WinDLL("version", use_last_error=True)
        version.GetFileVersionInfoSizeW.argtypes = [ctypes.c_wchar_p, ctypes.c_void_p]
        version.GetFileVersionInfoW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p]
        version.VerQueryValueW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p,
                                         ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_uint)]
        size = version.GetFileVersionInfoSizeW(str(EXE), None)
        self.assertGreater(size, 0)
        buf = ctypes.create_string_buffer(size)
        self.assertTrue(version.GetFileVersionInfoW(str(EXE), 0, size, buf))
        ptr, length = ctypes.c_void_p(), ctypes.c_uint()
        self.assertTrue(version.VerQueryValueW(buf, "\\", ctypes.byref(ptr), ctypes.byref(length)))
        fields = struct.unpack("13I", ctypes.string_at(ptr, 52))
        ms, ls = fields[2:4]
        self.assertEqual((ms >> 16, ms & 65535, ls >> 16, ls & 65535), (2, 1, 0, 31))


if __name__ == "__main__":
    unittest.main()
