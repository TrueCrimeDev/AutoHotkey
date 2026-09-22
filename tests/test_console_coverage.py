"""/Coverage=<path> LCOV regressions. Usage: python tests/test_console_coverage.py [AutoHotkey.exe]."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

EXE = Path(sys.argv.pop(1) if len(sys.argv) > 1 and not sys.argv[1].startswith("-")
           else "bin/AutoHotkey64.exe").resolve()

SAMPLE = """\
#Include inc.ahk
x := 3
if (x > 5) {
    Print("big")
} else {
    Print("small")
}
i := 0
while (i < 2) {
    i++
}
try {
    throw ValueError("boom")
} catch ValueError as e {
    caught := 1
}
switch x {
    case 1:
        never := 1
    case 3:
        three := 1
}
Print(Helper(2))

Helper(n) {
    if n > 1
        return n
    return 0
}
"""
INCLUDE = "IncFn() {\n    return 1\n}\nincVar := IncFn()\n"


def parse_lcov(text):
    records = {}
    current = None
    for line in text.splitlines():
        if line.startswith("SF:"):
            current = {"lines": {}, "LF": None, "LH": None}
            records[Path(line[3:]).name.lower()] = current
        elif line.startswith("DA:"):
            number, hits = line[3:].split(",")
            current["lines"][int(number)] = int(hits)
        elif line.startswith("LF:"):
            current["LF"] = int(line[3:])
        elif line.startswith("LH:"):
            current["LH"] = int(line[3:])
    return records


class CoverageTests(unittest.TestCase):
    def run_cli(self, *args, cwd=None):
        return subprocess.run([str(EXE), *map(str, args)], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=20, cwd=cwd,
                              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def write_sample(self, folder):
        (folder / "sample.ahk").write_text(SAMPLE, encoding="utf-8")
        (folder / "inc.ahk").write_text(INCLUDE, encoding="utf-8")
        return folder / "sample.ahk"

    def test_lcov_reflects_executed_lines(self):
        with tempfile.TemporaryDirectory(prefix="ahk-cov-") as td:
            folder = Path(td)
            script = self.write_sample(folder)
            out = folder / "cov.lcov"
            r = self.run_cli("/Headless", f"/Coverage={out}", script)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.splitlines(), ["small", "2"])
            records = parse_lcov(out.read_text(encoding="utf-8"))
            self.assertEqual(set(records), {"sample.ahk", "inc.ahk"})
            lines = records["sample.ahk"]["lines"]
            # Branches: the taken else body ran, the untaken if body did not.
            self.assertEqual(lines[4], 0)
            self.assertEqual(lines[6], 1)
            # Structural lines are not "found": else, catch, case, braces, function headers.
            for absent in (5, 7, 11, 14, 16, 18, 20, 22, 24, 25, 29):
                self.assertNotIn(absent, lines, f"line {absent} should not be reported")
            # While is counted once per condition evaluation (2 true + 1 false).
            self.assertEqual(lines[9], 3)
            self.assertEqual(lines[10], 2)
            # try/throw/catch body, switch, taken case, untaken case.
            self.assertEqual(lines[12], 1)
            self.assertEqual(lines[13], 1)
            self.assertEqual(lines[15], 1)
            self.assertEqual(lines[17], 1)
            self.assertEqual(lines[19], 0)
            self.assertEqual(lines[21], 1)
            self.assertEqual(lines[23], 1)
            # Function body: taken return hit, fall-through return not.
            self.assertEqual(lines[26], 1)
            self.assertEqual(lines[27], 1)
            self.assertEqual(lines[28], 0)
            # Nothing past the last source line.
            self.assertLessEqual(max(lines), 29)
            self.assertEqual(records["sample.ahk"]["LF"], len(lines))
            self.assertEqual(records["sample.ahk"]["LH"], sum(1 for h in lines.values() if h))
            inc = records["inc.ahk"]
            self.assertEqual(inc["lines"], {2: 1, 4: 1})
            self.assertEqual((inc["LF"], inc["LH"]), (2, 2))

    def test_relative_path_resolves_against_launch_directory(self):
        with tempfile.TemporaryDirectory(prefix="ahk-cov-") as td:
            folder = Path(td)
            (folder / "sub").mkdir()
            script = folder / "chdir.ahk"
            script.write_text('SetWorkingDir(A_ScriptDir "\\sub")\nx := 1\n', encoding="utf-8")
            r = self.run_cli("/Headless", "--coverage=rel.lcov", script, cwd=folder)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue((folder / "rel.lcov").is_file())
            self.assertFalse((folder / "sub" / "rel.lcov").exists())

    def test_report_survives_uncaught_error_and_test_failure(self):
        with tempfile.TemporaryDirectory(prefix="ahk-cov-") as td:
            folder = Path(td)
            script = folder / "boom.ahk"
            script.write_text('a := 1\nthrow Error("boom")\nb := 2\n', encoding="utf-8")
            out = folder / "boom.lcov"
            r = self.run_cli("/Headless", "/ErrorStdOut", f"/Coverage={out}", script)
            self.assertEqual(r.returncode, 10, r.stderr)
            lines = parse_lcov(out.read_text(encoding="utf-8"))["boom.ahk"]["lines"]
            self.assertEqual((lines[1], lines[2], lines[3]), (1, 1, 0))

            failing = folder / "fail.ahk"
            failing.write_text('ran := 1\nExitApp(14)\n', encoding="utf-8")
            out = folder / "fail.lcov"
            r = self.run_cli("/Headless", f"/Coverage={out}", "test", failing)
            self.assertEqual(r.returncode, 14, r.stderr)
            lines = parse_lcov(out.read_text(encoding="utf-8"))["fail.ahk"]["lines"]
            self.assertEqual(lines[1], 1)

    def test_flag_validation_and_capabilities(self):
        r = self.run_cli("/Coverage=", "x.ahk")
        self.assertEqual(r.returncode, 64, r.stderr)
        self.assertIn("/Coverage requires a non-empty path", r.stderr)
        r = self.run_cli("--capabilities")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIs(json.loads(r.stdout)["features"]["coverage"], True)
        r = self.run_cli("--help")
        self.assertIn("/Coverage=path", r.stdout)


if __name__ == "__main__":
    unittest.main()
