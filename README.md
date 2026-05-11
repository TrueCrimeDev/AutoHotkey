# AutoHotkey v2 Console Fork

<p>
  A focused AutoHotkey v2 fork for headless execution, structured runtime errors, and AI-assisted debugging via DBGp + MCP.
</p>

<p>
  <strong>Repository:</strong> <a href="https://github.com/TrueCrimeDev/AutoHotkey">TrueCrimeDev/AutoHotkey</a><br>
  <strong>Default branch:</strong> <code>alpha</code><br>
  <strong>Current engine tag:</strong> <code>2.1-alpha.26+Console</code>
</p>

## What This Version Changes

| Area | Change in this fork | Why it matters |
| --- | --- | --- |
| Runtime error handling | `/ErrorStdOut` routes runtime errors to `stderr` (`"**"`) instead of GUI-only dialogs | Works cleanly in terminals, scripts, CI, and agent loops |
| Headless mode | `/Headless` or `--headless` forces non-interactive operation | Prevents blocking dialogs in automation pipelines |
| Structured diagnostics | `/Diag=json` or `--diag=json` outputs JSON diagnostics | Easy machine parsing for agents and CI |
| Built-in check/test modes | `check` / `/Check` and `test` / `/Test` | Native syntax-check and single-script test flows |
| Error formatting | Error output includes file/line format, source line, optional call stack, optional ANSI color (`/ErrorStdOut:color`) | Easier for humans and tools to parse and act on |
| Exit behavior | Non-warning runtime errors return non-zero exit codes | Reliable failure detection in automation |
| Source context API | Adds `_ScriptGetLines(Filename, LineNumber, Range?)` | Lets tooling fetch exact nearby source text for debugging/fixes |
| Debugger integration | Preserves/extends DBGp workflow used by MCP tooling | Enables interactive AI debugging and inspection |

## How This Build Works

### 1. Command-line mode selection

- Standard run: `AutoHotkey64.exe script.ahk`
- Debugger mode: `AutoHotkey64.exe /Debug script.ahk`
- Headless error mode: `AutoHotkey64.exe /ErrorStdOut script.ahk`
- Hard headless mode: `AutoHotkey64.exe /Headless script.ahk`
- JSON diagnostics: `AutoHotkey64.exe /Headless /Diag=json script.ahk`
- Colored error mode: `AutoHotkey64.exe /ErrorStdOut:color script.ahk`
- Encoding override: `AutoHotkey64.exe /ErrorStdOut=UTF-8 script.ahk`
- Check mode: `AutoHotkey64.exe check script.ahk` (or `/Check script.ahk`)
- Test mode: `AutoHotkey64.exe test script.ahk` (or `/Test script.ahk`)

### 2. Runtime error pipeline

When `/ErrorStdOut` is enabled:

1. Errors pass through `Script::ShowError(...)`.
2. Output is formatted in `FormatStdErr(...)` (file, line, message, source context, stack context when available).
3. Text is written to `stderr` via `"**"` stream handling.
4. Fatal/critical paths exit with non-zero code, so external tooling can fail fast.

<details>
  <summary>Why stderr and not stdout?</summary>
  The historical switch name is <code>/ErrorStdOut</code>, but this fork writes runtime errors to <code>stderr</code> for compatibility with standard tooling and stream separation.
</details>

### 3. Exit code taxonomy

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `10` | Runtime error |
| `11` | Critical/internal error |
| `12` | Parse/load error |
| `13` | Check/validate failure |
| `14` | Test failure |
| `64` | CLI usage/argument error |

### 4. Stream behavior

- ``FileAppend "...`n", "*"`` writes to stdout
- ``FileAppend "...`n", "**"`` writes to stderr

This keeps normal script output and error output clearly separated for consumers.

## Why This Is Good for Claude Code and MCPs

This fork is practical for AI-assisted workflows because it provides deterministic, machine-usable signals:

1. Stable error channel: runtime failures go to `stderr`, so tools can capture them without scraping modal dialogs.
2. Parse-friendly text: error lines include file + line information in a consistent format.
3. Built-in source retrieval: `_ScriptGetLines()` gives precise nearby code context for analysis/fix generation.
4. Debug protocol support: the included DBGp pipeline works with the MCP server under `debugger-tool/mcp-server`.
5. Automation-safe exits: non-zero exit codes make retry/fix loops predictable.
6. Source intelligence tools: MCP now exposes symbol outlines and workspace symbol indexing.

In practice, this supports a tight loop:

`run script -> capture structured error -> inspect context/variables -> apply fix -> re-run`

## Quick Start

### Build (Windows)

```powershell
.\build_local.bat
```

Output:

- `bin\AutoHotkey64.exe`
- `build_vs18.cmd` is available when this machine only has Visual Studio Build Tools 18 installed.

### Verify console behavior

```powershell
bin\AutoHotkey64.exe test_console.ahk 1>out.txt 2>err.txt
bin\AutoHotkey64.exe /ErrorStdOut test_errorstdout.ahk 1>out.txt 2>err.txt
```

Expected:

- Regular script text appears in `out.txt`.
- Runtime error details appear in `err.txt`.

### Start MCP bridge for AI tools

```powershell
cd debugger-tool\mcp-server
npm install
npm run build
node build/index.js
```

Then launch script debugging:

```powershell
bin\AutoHotkey64.exe /Debug your_script.ahk
```

## Repository Map

<table>
  <thead>
    <tr>
      <th>Path</th>
      <th>Purpose</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>source/</code></td>
      <td>AutoHotkey engine source (C++)</td>
    </tr>
    <tr>
      <td><code>debugger-tool/mcp-server/</code></td>
      <td>MCP server bridging AI tools to AutoHotkey DBGp</td>
    </tr>
    <tr>
      <td><code>debugger-tool/ahk-error-agent/</code></td>
      <td>Error capture and fix automation tooling</td>
    </tr>
    <tr>
      <td><code>BUILD.md</code></td>
      <td>Build instructions for this repo</td>
    </tr>
  </tbody>
</table>

## Notes

- This is a specialized fork, not a drop-in claim of upstream parity.
- If you need stock behavior, use upstream AutoHotkey builds.
- For MCP usage details, see `debugger-tool/mcp-server/README.md`.
- Milestone implementation status is tracked in `V3_MILESTONE_STATUS.md`.
