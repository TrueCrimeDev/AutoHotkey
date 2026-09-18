---
title: Errors → AI → verified fix
description: Follow a real AutoHotkey error through a Claude Code diagnosis, a focused correction, and a verified Console rerun.
---

# Errors your AI can act on

An AI coding tool needs to see what went wrong. AutoHotkey Console sends failures to stderr, with the error class, message, source file, line, and statement. Claude Code can read that output alongside the script, propose a correction, and use a new execution result to check it.

**The main workflow is error feedback.** [Line Out](/console/line-out) adds the execution path; [Print](/console/print-json) adds values and results on stdout.

## 1. Capture a real failure

Download [error-demo.ahk](/examples/error-demo.ahk):

```ahk
#Requires AutoHotkey v2.1-alpha.30
settings := Map()
settings["retries"] := 3
attempts := settings["retry"]
```

Run it with a compatible Console executable. The examples use the [temporary `ahk` PowerShell alias](/guide/installation#add-a-temporary-powershell-alias):

```powershell
ahk /Headless /Diag=json .\error-demo.ahk
$LASTEXITCODE
```

The recorded process exited **10**. stdout was empty. These are selected fields from its stderr JSON; the file path is shortened:

```json
{
  "type": "UnsetItemError",
  "code": 10,
  "message": "Item has no value.",
  "extra": "[\"retry\"]",
  "file": "error-demo.ahk",
  "line": 4,
  "source": "attempts := settings[\"retry\"]"
}
```

The AI has a specific file to inspect, a failing line, and the missing key. The [diagnostic schema](/console/diagnostics) also carries severity and available stack information. A syntax check alone accepts this example: the missing key is a runtime failure.

## 2. Let Claude read the error

Claude Code received the source and captured diagnostic. Its recorded diagnosis was:

> Line 4 reads key "retry", but the Map only defines "retries". The missing key has no value, so AutoHotkey raises UnsetItemError (code 10).

It returned this single-line replacement:

```ahk
attempts := settings["retries"]
```

This correction uses the key already defined in the script. The full response and Console evidence are available in the [recorded example data](/examples/ai-error-feedback.json).

## 3. Verify the correction

Download [error-demo-fixed.ahk](/examples/error-demo-fixed.ahk), then check and run it:

```powershell
ahk /Headless /Diag=json check .\error-demo-fixed.ahk
ahk /Headless /Diag=json .\error-demo-fixed.ahk
$LASTEXITCODE
```

| Recorded check | Result |
| --- | --- |
| Syntax check | Exit 0 |
| Runtime rerun | Exit 0 |
| stderr | Empty |
| Separate runtime assertion | `attempts = 3` passed |

The rerun demonstrates that the failure is gone. The assertion checks that the corrected lookup returned the expected value.

## Bring this into Claude Code

[ClautoHotkey](/clautohotkey/setup) connects edits to interpreter checks. Its [post-edit workflow](/clautohotkey/workflow) returns validation feedback after Write/Edit; a configured runtime probe can also catch failures like this one. Native [MCP tools](/clautohotkey/mcp) expose captured streams and parsed diagnostics to a local tool client.

Ask Claude to keep the loop explicit:

```text
Run this script with the configured Console interpreter and capture stderr
and the exit code. Read any diagnostic and inspect its source location.
Make a focused correction, rerun the script, and assert the expected result.
Report the failure, the change, and the checks that actually ran.
```

## How this demo was verified

Recorded September 18, 2026 with AutoHotkey v2.1-alpha.31+Console, revision `a72a652123b7-dirty`. The example declares the compatible alpha.30 baseline.

The failing script was executed and its stderr captured. Claude Code then read that source and diagnostic with tools disabled and returned a diagnosis and replacement line. The returned correction was applied separately, followed by a Console syntax check, runtime rerun, and runtime assertion. This particular capture does **not** demonstrate automatic editing through a ClautoHotkey hook; the [session gallery](/showcase) contains separate hook evidence.

The website replays the recorded steps. It does not run an interpreter or contact an AI from your browser. Published file paths are reduced to filenames.
