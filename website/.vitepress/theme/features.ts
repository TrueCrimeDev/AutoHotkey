export const features = [
  {
    title: "Structured diagnostics",
    group: "Console",
    tag: "ERRORS",
    description:
      "Give AI the error type, source location, failing statement, and exit code it needs to diagnose a script.",
    path: "/console/diagnostics",
    code: "ahk /Headless /Diag=json script.ahk\n# stderr → diagnostic JSON; stdout → results",
    result: "Runtime error: 10 · check failure: 13 · test failure: 14",
  },
  {
    title: "Line Out & trace",
    group: "Console",
    tag: "EXECUTION",
    description:
      "Follow the statements that actually ran, with source files and line numbers to explain the path to a failure.",
    path: "/console/line-out",
    code: "ahk /Trace .\\script.ahk",
    result: "stderr: source file · line number · executing statement",
  },
  {
    title: "Print & JSON",
    group: "Console",
    tag: "DATA",
    description:
      "Turn a script into a composable command-line tool, with UTF-8 output and native JSON.",
    path: "/console/print-json",
    code: "data := JSON.Parse('{\"ready\":true}')\nPrint(JSON.Stringify(data))",
    result: '{"ready":true}',
  },
  {
    title: "Persistent REPL",
    group: "Console",
    tag: "EXPLORE",
    description:
      "Keep state between expressions. Explore functions and recover from invalid input.",
    path: "/console/eval-repl",
    code: "ahk repl\n>>> count := 21\n>>> count * 2",
    result: "42",
  },
  {
    title: "Inspect & Check",
    group: "Console",
    tag: "INTROSPECTION",
    description:
      "Describe values as JSON and ask the interpreter to check source before running it.",
    path: "/console/inspect-check",
    code: 'Print(Inspect(["alpha", 31]))\nresult := Check("x := 1")\nPrint(result.Ok)',
    result: "Array metadata · parse verdict: 1",
  },
  {
    title: "ProcessPipe",
    group: "Console",
    tag: "PROCESSES",
    description:
      "Exchange UTF-8 lines with a child process and manage its lifetime.",
    path: "/console/process-pipe",
    code: 'p := ProcessPipe(A_AhkPath, ["/Headless", "child.ahk"])\nPrint(p.ReadLine(10))\np.Wait(10)',
    result: "Separate stdout / stderr · timeouts · process-tree cleanup",
  },
  {
    title: "Automatic edit checks",
    group: "ClautoHotkey",
    tag: "FEEDBACK",
    description:
      "A real Claude Code hook checks AHK syntax after Write or Edit, with an optional runtime probe.",
    path: "/clautohotkey/workflow",
    code: "Claude Code → Write / Edit an .ahk file\nClautoHotkey → ahk-post-edit.sh\nConsole → syntax + bounded runtime check",
    result: "An edit becomes a concrete validation result.",
  },
  {
    title: "Skills & knowledge",
    group: "ClautoHotkey",
    tag: "CONTEXT",
    description:
      "Load task-specific AHK guidance for GUIs, COM, classes, debugging, and more.",
    path: "/clautohotkey/skills",
    code: "/ahk-oop\n/ahk-fix\n/ahk-versions",
    result: "19 commands · path-triggered rules · structured modules",
  },
  {
    title: "Grading gates",
    group: "ClautoHotkey",
    tag: "EVIDENCE",
    description:
      "Keep static and dry-run findings, parser confidence, and intercepted effects in a shared format.",
    path: "/clautohotkey/harness",
    code: "GateStatic.ahk → ahk-harness/result@1\nGateDryRun.ahk → residency + intent\nCheckResults.py → accept or flag evidence",
    result: "A pass is specific to its tier; partial parsing stays visible.",
  },
  {
    title: "Native MCP tools",
    group: "Together",
    tag: "INTEGRATION",
    description:
      "Let a local tool client check, run, test, and explore source through the same engine.",
    path: "/clautohotkey/mcp",
    code: "AutoHotkey64Console.exe mcp\n# JSON-RPC over stdio\n# discover tools/list before calling tools",
    result: "8 tools in the demonstrated development build",
  },
  {
    title: "Test → inspect → repair",
    group: "Together",
    tag: "WORKFLOW",
    description:
      "Combine assertions, structured failures, and source context into a repeatable repair loop.",
    path: "/recipes/testing-ci",
    code: "ahk check tests.ahk\nahk /Headless /Diag=json test tests.ahk\n# Inspect failures, edit, then rerun.",
    result: "Runtime assertions verify behavior beyond syntax.",
  },
  {
    title: "Crash forensics",
    group: "Console",
    tag: "DIAGNOSTICS",
    description:
      "Preserve startup, error, and exit events when stderr alone is not enough.",
    path: "/console/crash-logs",
    code: "ahk /CrashLog=events.log /Headless script.ahk",
    result: "Append-only event log · source context · exit reason",
  },
];
