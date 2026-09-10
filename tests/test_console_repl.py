"""Behavioral tests for the console REPL. Usage: python tests/test_console_repl.py ENGINE"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ENGINE = Path(sys.argv.pop(1)).resolve()
REPO = Path(__file__).resolve().parents[1]

class ReplTests(unittest.TestCase):
    def run_repl(self, text, json_mode=True, script=None):
        args = [str(ENGINE), "repl", "/Headless"]
        if json_mode:
            args.append("/Diag=json")
        if script:
            args.append(str(script))
        return subprocess.run(args, input=text.encode("utf-8") if isinstance(text, str) else text,
            capture_output=True, cwd=REPO, timeout=10,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def records(self, p):
        self.assertEqual(p.returncode, 0, p.stderr.decode("utf-8", "replace"))
        return [json.loads(line) for line in p.stdout.decode("utf-8").splitlines()]

    def test_unmatched_delimiters_recover_and_keep_state(self):
        for expr in ["]", "}", ")", "[)", "([)]", "x := [", "f := () => (", "f := (x) => x +", '"unclosed']:
            with self.subTest(expression=expr):
                rows = self.records(self.run_repl("saved := 41\n" + expr + "\nsaved+1\n(() => 42)()\n"))
                self.assertEqual(len(rows), 4)
                self.assertFalse(rows[1]["ok"])
                self.assertEqual(rows[1]["type"], "SyntaxError")
                self.assertEqual(rows[2]["value"], "42")
                self.assertEqual(rows[3]["value"], "42")

    def test_inline_function_maybe_operator_is_resolved(self):
        rows = self.records(self.run_repl("(() => unsetLocal? || 42)()\n40+2\n"))
        # Match normal script semantics: the maybe expression returns Unset.
        self.assertEqual(rows[0]["type"], "Unset")
        self.assertEqual([r["value"] for r in rows], ["", "42"])
        self.assertTrue(all(r["ok"] for r in rows))

    def test_failed_assignment_keeps_existing_variable_lookup(self):
        rows = self.records(self.run_repl("zSaved := 41\naNew := (\nzSaved+1\n"))
        self.assertFalse(rows[1]["ok"])
        self.assertEqual(rows[2]["value"], "42")

    def test_function_expressions_keep_working_across_inputs(self):
        rows = self.records(self.run_repl("f := (x) => x+1\nf(41)\n((x) => x+1)(41)\n42\n"))
        self.assertTrue(all(r["ok"] for r in rows))
        self.assertEqual([r["value"] for r in rows[1:]], ["42", "42", "42"])

    def test_full_long_result_and_embedded_nul(self):
        rows = self.records(self.run_repl('Format("{:05000}", 1)\n"a" Chr(0) "b"\n'))
        self.assertEqual(rows[0]["value"], "0" * 4999 + "1")
        self.assertEqual(rows[1]["value"], "a\0b")

    def test_unicode_escaping_roundtrips(self):
        rows = self.records(self.run_repl('"héllo 日本語 😀" Chr(1) Chr(10)\n'))
        self.assertEqual(rows[0]["value"], "héllo 日本語 😀\x01\n")

    def test_script_output_goes_to_stderr_and_results_stay_json(self):
        p = self.run_repl('Print("printed")\nFileAppend("appended", "*", "UTF-8-RAW")\nf := FileOpen("*", "w", "UTF-8-RAW"), f.Write("written"), f.Close()\n42\n')
        rows = self.records(p)
        self.assertEqual(len(rows), 4)
        self.assertEqual(rows[-1]["value"], "42")
        err = p.stderr.decode("utf-8")
        for s in ["printed", "appended", "written"]:
            self.assertIn(s, err)

    def test_host_startup_output_is_separate(self):
        with tempfile.TemporaryDirectory(prefix="ahk-repl-", dir=REPO / "temp") as d:
            script = Path(d) / "host.ahk"
            script.write_text('Print("startup")\nglobal counter := 40\n', encoding="utf-8")
            p = self.run_repl("counter+2\n", script=script)
            self.assertEqual(self.records(p)[0]["value"], "42")
            self.assertIn(b"startup", p.stderr)

    def test_blank_help_and_exit_are_framed(self):
        rows = self.records(self.run_repl("\n.help\n42\n.exit\n"))
        self.assertEqual(len(rows), 4)
        self.assertTrue(all(r["ok"] for r in rows))
        self.assertIn("REPL", rows[1]["value"])
        self.assertEqual(rows[2]["value"], "42")

    def test_first_bom_and_crlf_are_accepted(self):
        rows = self.records(self.run_repl("\ufeff40+2\r\n43"))
        self.assertEqual([r["value"] for r in rows], ["42", "43"])

    def test_invalid_utf8_is_rejected_without_losing_next_input(self):
        rows = self.records(self.run_repl(b'"\xff"\n42\n'))
        self.assertFalse(rows[0]["ok"])
        self.assertEqual(rows[1]["value"], "42")

    def test_text_mode_keeps_plain_output(self):
        p = self.run_repl('Print("hello")\nx := 4\nx*10\n', json_mode=False)
        self.assertEqual(p.returncode, 0)
        self.assertEqual(p.stdout.decode("utf-8").splitlines(), ["hello", "", "4", "40"])

if __name__ == "__main__":
    unittest.main()
