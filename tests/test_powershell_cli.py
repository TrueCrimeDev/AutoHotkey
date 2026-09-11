"""Exercise the ahk shortcut through real PowerShell processes.

Usage: python tests/test_powershell_cli.py [--wrapper tools/ahk.ps1]
Omit --wrapper to check the installed user profiles.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

parser = argparse.ArgumentParser()
parser.add_argument("--wrapper", type=Path)
options, remaining = parser.parse_known_args()
ROOT = Path(__file__).resolve().parents[1]
SHELLS = [p for p in (shutil.which("pwsh"),
    str(Path(os.environ["WINDIR"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"))
    if p and Path(p).is_file()]


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


class PowerShellCliTests(unittest.TestCase):
    def run_ps(self, shell, command, cwd=None):
        bootstrap = "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)\n$OutputEncoding = [Text.UTF8Encoding]::new($false)\n"
        args = [shell, "-NoLogo", "-NonInteractive"]
        if options.wrapper:
            args.append("-NoProfile")
            bootstrap += ". " + quote(options.wrapper.resolve()) + "\n"
        encoded = base64.b64encode((bootstrap + command).encode("utf-16le")).decode()
        return subprocess.run([*args, "-EncodedCommand", encoded], cwd=cwd or ROOT,
                              capture_output=True, timeout=12)

    def check_all(self, command, expected, code=0, cwd=None):
        for shell in SHELLS:
            with self.subTest(shell=Path(shell).name, command=command):
                p = self.run_ps(shell, command, cwd)
                out = p.stdout.decode("utf-8", "replace").replace("\r", "")
                err = p.stderr.decode("utf-8", "replace")
                self.assertEqual(p.returncode, code, out + err)
                self.assertIn(expected, out + err)

    def test_bare_command(self):
        self.check_all("ahk", "2.1-alpha.31+Console")

    def test_help_spellings(self):
        for spelling in ("help", "-h", "--h", "-help", "--help"):
            self.check_all("ahk " + spelling, "Usage:")

    def test_run_without_script_reports_usage(self):
        self.check_all("ahk run; exit $LASTEXITCODE", "script", 64)

    def test_missing_script_is_visible(self):
        self.check_all("ahk ./missing-cli-probe-792628.ahk; exit $LASTEXITCODE",
                       "not found", 12)

    def test_script_and_run_alias_preserve_arguments(self):
        with tempfile.TemporaryDirectory(prefix="ahk-cli-shell-", dir=ROOT / "temp") as td:
            script = Path(td) / "argument demo.ahk"
            script.write_text('for arg in A_Args\n    Print(arg)\nExitApp(7)\n', encoding="utf-8")
            for prefix in ("", "run "):
                # Use each shell's native quoting rules; Windows PowerShell 5.1
                # requires literal escaping for quotes and empty native arguments.
                setup = "$nativeArgs = @('two words', '--help', 'quote\"inside', '')\n"
                setup += "if ($PSVersionTable.PSVersion.Major -lt 7) { $nativeArgs = @('two words', '--help', 'quote\\\"inside', '\"\"') }\n"
                self.check_all(setup + "ahk " + prefix + quote(script.name)
                               + " @nativeArgs; exit $LASTEXITCODE",
                               'two words\n--help\nquote"inside\n\n', 7, td)

    def test_check_and_test_modes(self):
        with tempfile.TemporaryDirectory(prefix="ahk-cli-shell-", dir=ROOT / "temp") as td:
            script = Path(td) / "safe.ahk"
            script.write_text('Print("script ran")\n', encoding="utf-8")
            self.check_all("ahk check /Diag=json " + quote(script), '"status":"pass"')
            self.check_all("ahk test " + quote(script), "script ran")

    def test_pipeline_repl_receives_input_and_returns_json(self):
        command = "'40+2' | ahk repl /Diag=json | ConvertFrom-Json | ForEach-Object { 'RESULT=' + $_.value }"
        self.check_all(command, "RESULT=42")

    def test_pipeline_unicode_roundtrip(self):
        command = "'\"日本語 😀\"' | ahk repl /Diag=json | ConvertFrom-Json | ForEach-Object { 'RESULT=' + $_.value }"
        self.check_all(command, "RESULT=日本語 😀")

    def test_mcp_stdio_survives_wrapper(self):
        request = json.dumps({"jsonrpc":"2.0", "id":1, "method":"ping"})
        self.check_all(quote(request) + " | ahk mcp | ConvertFrom-Json | ForEach-Object { 'ID=' + $_.id }", "ID=1")

    def test_unknown_option_is_visible(self):
        self.check_all("ahk --not-a-real-option; exit $LASTEXITCODE", "Unknown option", 64)


if __name__ == "__main__":
    unittest.main(argv=[__file__, *remaining])
