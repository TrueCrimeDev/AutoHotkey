export const steps = [
  {
    name: "01 Write",
    language: "ahk",
    label: "demo.ahk",
    code: '#Requires AutoHotkey v2.1-alpha.31\n#EnableEval\n\nconfig := JSON.Parse(\'{"count":21}\')\ncount := config["count"]\nPrint("answer={}", Eval("count * 2"))',
    output: "Write / Edit triggers ClautoHotkey’s post-edit validation.",
  },
  {
    name: "02 Validate",
    language: "ini",
    label: "ClautoHotkey hook",
    code: 'harness.env\n  AHK_BIN_WIN="C:\\Tools\\AutoHotkey64Console.exe"\n  AHK_DIAG_JSON=1\n  RUNTIME_PROBE=1\n\nahk-post-edit.sh → configured interpreter',
    output: "Syntax check first. Optional bounded runtime probe next.",
  },
  {
    name: "03 Execute",
    language: "powershell",
    label: "PowerShell",
    code: "ahk /Headless /Diag=json demo.ahk\n\nanswer=42\n\n# stdout: result\n# stderr: diagnostics\n# exit code: 0",
    output:
      "Expected output for this example. Run it with a compatible local build.",
  },
  {
    name: "04 Inspect",
    language: "json",
    label: "Local MCP client",
    code: '{\n  "name": "check",\n  "arguments": {\n    "file": "C:\\Scripts\\demo.ahk"\n  }\n}',
    output:
      "Check returns a parse verdict. Use test and assertions to verify behavior.",
  },
];
