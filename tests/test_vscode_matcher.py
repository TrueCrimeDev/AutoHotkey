"""The VS Code problem matcher for /Diag=json, and the LSP syntaxes generator. Usage: python tests/test_vscode_matcher.py ENGINE

tools/vscode/tasks.template.json carries an "ahk" problemMatcher whose one
regexp turns the engine's /Diag=json diagnostics (one JSON object per line on
stderr, schema 2) into Problems entries. This suite runs ENGINE on a file with a
syntax error (check) and on a file that throws (run), compiles the template's
regexp with Python's re after converting JavaScript-only syntax, and checks what
it captures from the real records: severity, message, file, line and column
(captured only when not 0). It also checks that ordinary output never matches,
that the three engine tasks in the fork's own .vscode/tasks.json carry the same
matcher and pass /Diag=json, and that tools/vscode/gen_syntaxes.py builds the
AutoHotkey2.Syntaxes folder from an extension folder idempotently.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


ENGINE = Path(sys.argv.pop(1)).resolve()
ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "tools/vscode/tasks.template.json"
FORK_TASKS = ROOT / ".vscode/tasks.json"
GENERATOR = ROOT / "tools/vscode/gen_syntaxes.py"
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
DIAG_PREFIX = '{"kind":"diagnostic",'
# Lines a task terminal shows that must never become a Problems entry.
ORDINARY_LINES = [
    "before",
    "CHECK PASS",
    '{"kind":"check","status":"pass"}',
    '{"kind":"result","ok":true,"type":"Integer","value":"42"}',
    '{"event":"statement","file":"C:\\\\app\\\\App.ahk","line":27,"function":"SaveRecord","thread":1,"text":"x += 1"}',
    "C:\\app\\App.ahk (4) : ==> boom",
    "C:\\app\\App.ahk (1) : ==> Warning: This global variable appears to never be assigned a value.",
    "     Specifically: extra",
    "        > 4|     throw ValueError(\"boom\")",
    # A debugger notice carries no file; it belongs in the terminal, not in Problems.
    '{"kind":"diagnostic","format":"json","schema":2,"severity":"warning","type":"Warning","code":0,'
    '"message":"Could not connect to localhost:9001; continuing without the debugger.","extra":"localhost:9001",'
    '"what":"Debugger","file":"","line":0,"column":0,"source":"","stack":""}',
    ' {"kind":"diagnostic","format":"json","schema":2,"severity":"error","type":"Error","code":13,'
    '"message":"indented","extra":"","what":"","file":"C:\\\\a.ahk","line":1,"column":0,"source":"","stack":""}',
]


def load_jsonc(path):
    """JSON with // and /* */ comments (outside strings) and trailing commas, as VS Code reads it."""
    text = path.read_text(encoding="utf-8-sig")
    out = []
    i = 0
    n = len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        else:
            out.append(c)
        i += 1
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))


def js_regexp_to_python(source):
    """A VS Code pattern regexp is a JavaScript RegExp; map the syntax Python spells differently."""
    source = re.sub(r"\(\?<(?![=!])", "(?P<", source)  # named groups, not look-behind
    return re.compile(source.replace("\\/", "/"))


class Matcher:
    def __init__(self, problem_matcher):
        self.definition = problem_matcher
        pattern = problem_matcher["pattern"]
        self.regexp = js_regexp_to_python(pattern["regexp"])
        self.groups = {name: pattern[name] for name in ("file", "line", "column", "severity", "message")}

    def match(self, line):
        """The captures VS Code would use, or None. An unmatched group is left out, as VS Code leaves it."""
        found = self.regexp.match(line)
        if not found:
            return None
        return {name: found.group(index) for name, index in self.groups.items() if found.group(index) is not None}


def decode(json_string_body):
    """The value of a JSON string whose quotes the regexp stripped (what VS Code does NOT do)."""
    return json.loads('"' + json_string_body + '"')


def same_file(a, b):
    return os.path.normcase(str(Path(a).resolve())) == os.path.normcase(str(Path(b).resolve()))


class ProblemMatcherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = load_jsonc(TEMPLATE)
        cls.matcher = Matcher(cls.template["tasks"][0]["problemMatcher"])

    def run_engine(self, *args):
        return subprocess.run([str(ENGINE), *map(str, args)], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=30, creationflags=CREATE_NO_WINDOW)

    def records(self, stderr):
        lines = [line for line in stderr.splitlines() if line.startswith(DIAG_PREFIX)]
        for line in lines:
            record = json.loads(line)
            self.assertEqual(record["schema"], 2, line)
        return lines

    def test_template_tasks_share_one_matcher_and_diag_json(self):
        tasks = self.template["tasks"]
        self.assertEqual({t["label"] for t in tasks}, {"Run AHK (fork)", "Check AHK (fork)", "Test AHK (fork)",
                                                       "Trace AHK (fork)", "Coverage AHK (fork)"})
        for task in tasks:
            with self.subTest(task=task["label"]):
                self.assertEqual(task["problemMatcher"], self.matcher.definition)
                self.assertEqual(task["command"],
                                 "${env:USERPROFILE}\\Documents\\Design\\Coding\\AutoHotkey\\bin\\AutoHotkey64Console.exe")
                self.assertIn("/Diag=json", task["args"])
                self.assertEqual(task["args"][-1], "${file}")
        definition = self.matcher.definition
        self.assertEqual(definition["owner"], "ahk")
        self.assertEqual(definition["fileLocation"], "absolute")
        self.assertEqual(definition["severity"], "error")

    def test_check_syntax_error_record(self):
        with tempfile.TemporaryDirectory(prefix="ahk-matcher-") as td:
            script = Path(td) / "bad.ahk"
            script.write_text("x := (1 +\nPrint(x)\n", encoding="utf-8")
            r = self.run_engine("check", "/Diag=json", script)
            self.assertEqual(r.returncode, 13, r.stderr)
            self.assertEqual(r.stdout, "")
            lines = self.records(r.stderr)
            self.assertEqual(len(lines), 1, r.stderr)
            record = json.loads(lines[0])
            captured = self.matcher.match(lines[0])
            self.assertIsNotNone(captured, lines[0])
            self.assertEqual(captured["severity"], "error")
            self.assertEqual(captured["line"], "1")
            self.assertNotIn("column", captured)  # the engine reports column 0: VS Code marks the whole line
            self.assertEqual(decode(captured["message"]), record["message"])
            self.assertIn('\\"', captured["message"])  # the raw JSON text, quotes still escaped
            self.assertTrue(same_file(decode(captured["file"]), script), captured["file"])
            self.assertIn("\\\\", captured["file"])  # VS Code's normalize() collapses the doubled separators

    def test_run_uncaught_error_record(self):
        with tempfile.TemporaryDirectory(prefix="ahk-matcher-") as td:
            script = Path(td) / "boom.ahk"
            script.write_text('Print("before")\nFn()\nFn() {\n'
                              '    throw ValueError("boom `"quoted`" \\ slash", -1, "extra `t tab")\n}\n',
                              encoding="utf-8")
            r = self.run_engine("run", "/Diag=json", "/Headless", script)
            self.assertEqual(r.returncode, 10, r.stderr)
            self.assertEqual(r.stdout.strip(), "before")
            lines = self.records(r.stderr)
            self.assertEqual(len(lines), 1, r.stderr)
            record = json.loads(lines[0])
            self.assertEqual((record["type"], record["what"], record["code"]), ("ValueError", "Fn", 10))
            self.assertEqual(record["extra"], "extra \t tab")
            captured = self.matcher.match(lines[0])
            self.assertIsNotNone(captured, lines[0])
            self.assertEqual(captured["severity"], "error")
            self.assertEqual(captured["line"], "4")
            self.assertNotIn("column", captured)
            self.assertEqual(decode(captured["message"]), 'boom "quoted" \\ slash')
            self.assertEqual(decode(captured["message"]), record["message"])
            self.assertTrue(same_file(decode(captured["file"]), script), captured["file"])
            self.assertIsNone(self.matcher.match("before"))

    def test_check_warning_record_is_a_warning(self):
        with tempfile.TemporaryDirectory(prefix="ahk-matcher-") as td:
            script = Path(td) / "warn.ahk"
            script.write_text("y := neverAssigned\nPrint(y)\n", encoding="utf-8")
            r = self.run_engine("check", "/Diag=json", script)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.strip(), '{"kind":"check","status":"pass"}')
            self.assertIsNone(self.matcher.match(r.stdout.strip()))
            lines = self.records(r.stderr)
            self.assertEqual(len(lines), 1, r.stderr)
            captured = self.matcher.match(lines[0])
            self.assertIsNotNone(captured, lines[0])
            self.assertEqual(captured["severity"], "warning")
            self.assertEqual(captured["line"], "1")
            self.assertEqual(decode(captured["message"]), json.loads(lines[0])["message"])
            self.assertTrue(same_file(decode(captured["file"]), script), captured["file"])

    def test_ordinary_output_never_matches(self):
        for line in ORDINARY_LINES:
            with self.subTest(line=line):
                self.assertIsNone(self.matcher.match(line))

    def test_nonzero_column_and_critical_severity(self):
        line = ('{"kind":"diagnostic","format":"json","schema":2,"severity":"critical","type":"Error","code":11,'
                '"message":"m","extra":"","what":"","file":"C:\\\\a.ahk","line":12,"column":7,"source":"","stack":""}')
        captured = self.matcher.match(line)
        self.assertEqual(captured, {"file": "C:\\\\a.ahk", "line": "12", "column": "7",
                                    "severity": "critical", "message": "m"})

    def test_fork_tasks_use_the_template_matcher(self):
        tasks = {task["label"]: task for task in load_jsonc(FORK_TASKS)["tasks"]}
        for label in ("Check AHK (fork)", "Run AHK (fork, color)", "Test AHK (fork)"):
            with self.subTest(task=label):
                task = tasks[label]
                self.assertEqual(task["problemMatcher"], self.matcher.definition)
                self.assertIn("/Diag=json", task["args"])
                self.assertTrue(task["command"].endswith("AutoHotkey64Console.exe"), task["command"])
                self.assertEqual(task["args"][-1], "${file}")


class GenSyntaxesTests(unittest.TestCase):
    """gen_syntaxes.py on a stand-in extension folder, so the machine's VS Code is not involved."""

    BUNDLED_D = ";@region vars\r\n; The AutoHotkey path.\r\nA_AhkPath: String\r\n;@endregion\r\n"
    BUNDLED_JSON = {"directives": [{"body": "#Warn", "description": "bundled"}], "keywords": []}

    def generate(self, ext, out):
        r = subprocess.run([sys.executable, str(GENERATOR), "--lsp-dir", str(ext), "--out", str(out)],
                           capture_output=True, text=True, encoding="utf-8", timeout=60, cwd=ROOT,
                           creationflags=CREATE_NO_WINDOW)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout

    def snapshot(self, out):
        return {p.relative_to(out).as_posix(): p.read_bytes() for p in out.rglob("*") if p.is_file()}

    def test_generates_bundled_plus_fork_idempotently(self):
        with tempfile.TemporaryDirectory(prefix="ahk-syntaxes-") as td:
            ext = Path(td) / "thqby.vscode-autohotkey2-lsp-9.9.9"
            syntaxes = ext / "syntaxes"
            (syntaxes / "zh-cn").mkdir(parents=True)
            (ext / "package.json").write_text('{"version": "9.9.9"}', encoding="utf-8")
            for folder in (syntaxes, syntaxes / "zh-cn"):
                (folder / "ahk2.d.ahk").write_bytes(self.BUNDLED_D.encode("utf-8"))
                (folder / "ahk2.json").write_text(json.dumps(self.BUNDLED_JSON, indent="\t") + "\r\n",
                                                  encoding="utf-8", newline="")
            (syntaxes / "ahk2_common.json").write_text('{"methods": []}', encoding="utf-8")
            (syntaxes / "ahk2.tmLanguage.json").write_text("{}", encoding="utf-8")
            out = Path(td) / "generated"

            stdout = self.generate(ext, out)
            first = self.snapshot(out)
            self.assertEqual(set(first), {"ahk2.d.ahk", "ahk2.json", "zh-cn/ahk2.d.ahk", "zh-cn/ahk2.json",
                                          "ahk2_common.json", "ahk2.tmLanguage.json", "fork-syntaxes.json"})
            self.assertIn(f'"AutoHotkey2.Syntaxes": {json.dumps(str(out))}', stdout)
            self.assertIn("vscode-autohotkey2-lsp 9.9.9", stdout)
            self.assertEqual(first["ahk2_common.json"], b'{"methods": []}')

            fork = (ROOT / "fork.d.ahk").read_text(encoding="utf-8-sig")
            for name in ("ahk2.d.ahk", "zh-cn/ahk2.d.ahk"):
                text = first[name].decode("utf-8")
                self.assertTrue(text.startswith(self.BUNDLED_D.rstrip("\r\n")), name)
                self.assertEqual(text.count(";@region fork (AutoHotkey 2.1-alpha.33+Console)"), 1, name)
                self.assertEqual(text.count("\n") + 1, text.count("\r\n") + 1, "line endings follow the bundled file")
                for declaration in ("Eval(Expression) => ", "Print(Fmt?, Values*) => void", "Check(Source) => Object",
                                    "Inspect(Value, Depth := 2, MaxItems := 100) => String", "TSParse(Source) => Object",
                                    "class SyntaxError extends Error {", "class JSON extends Object {",
                                    "class ProcessPipe extends Object {"):
                    self.assertIn(declaration, text, name)
                self.assertNotIn("@since", text, "the server would enforce @since inside ahk2.d.ahk")
                self.assertIn(" * Since engine 2.1-alpha.29+Console.", text)
                self.assertNotIn(";@include", text, "the loading instructions of fork.d.ahk's header are dropped")
                self.assertIn(" * Evaluates one AutoHotkey expression in the caller's scope", text,
                              "the fork's documentation comments are kept")
                self.assertNotIn("\r\r", text)
                self.assertIn("@since", fork)
            for name in ("ahk2.json", "zh-cn/ahk2.json"):
                data = json.loads(first[name].decode("utf-8"))
                prefixes = [d.get("prefix") or d["body"] for d in data["directives"]]
                self.assertEqual(prefixes, ["#Warn", "#EnableEval", "#CrashLog"], name)
                self.assertEqual(data["keywords"], [])
                self.assertEqual(data["directives"][2]["body"], "#CrashLog ${1:Path}")
                self.assertIn("\r\n", first[name].decode("utf-8"))

            self.generate(ext, out)
            self.assertEqual(self.snapshot(out), first, "a second run rewrites the same files")

            # An extension update drops zh-cn/: the next run removes what the previous one generated there.
            (syntaxes / "zh-cn" / "ahk2.json").unlink()
            (syntaxes / "zh-cn" / "ahk2.d.ahk").unlink()
            (out / "user.snippet.json").write_text("{}", encoding="utf-8")
            self.generate(ext, out)
            third = self.snapshot(out)
            self.assertNotIn("zh-cn/ahk2.json", third)
            self.assertNotIn("zh-cn/ahk2.d.ahk", third)
            self.assertIn("user.snippet.json", third, "files the user added are kept")

    def test_refuses_the_extension_folder_as_output(self):
        with tempfile.TemporaryDirectory(prefix="ahk-syntaxes-") as td:
            ext = Path(td) / "ext"
            (ext / "syntaxes").mkdir(parents=True)
            (ext / "syntaxes" / "ahk2.d.ahk").write_text("", encoding="utf-8")
            (ext / "syntaxes" / "ahk2.json").write_text("{}", encoding="utf-8")
            r = subprocess.run([sys.executable, str(GENERATOR), "--lsp-dir", str(ext), "--out", str(ext / "syntaxes")],
                               capture_output=True, text=True, encoding="utf-8", timeout=60, cwd=ROOT,
                               creationflags=CREATE_NO_WINDOW)
            self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
            self.assertIn("must be outside", r.stderr)
            self.assertEqual((ext / "syntaxes" / "ahk2.d.ahk").read_text(encoding="utf-8"), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
