---
name: uia
description: Use before any Windows UI inspection or automation with the mcp__ahk__uia_* tools (the ahk server's uia toolset, off by default; needs the fork engine). Enforces the windows -> tree -> find -> element -> highlight funnel and the act-via-verified-snippet rule.
---

# UIA funnel: inspect with uia_*, act through the fork engine

The `mcp__ahk__uia_*` tools belong to the user-wide `ahk` MCP server. They are
READ-ONLY: they read properties and pattern state and never press anything.
To act, paste the verified snippet a tool returns into a script and run that
script with this repo's fork engine.

## Before the first call

1. **Is the toolset on?** The six tools are in the `ahk` server's `uia`
   toolset, which is off by default (only `core` is listed). If
   `mcp__ahk__uia_windows` is not in your tool list (deferred tools count),
   do not call it; ask the user before enabling. Two routes:
   - The user adds `uia` to `AHK_MCP_TOOLSETS` (for example `core,uia`) in
     the `ahk` server registration and restarts the server.
   - With the user's go-ahead, call
     `mcp__ahk__AHK_Settings {"action":"enable_toolset","toolset":"uia"}`.
     This persists machine-wide in `%APPDATA%\ahk-mcp\tool-settings.json`,
     applies to every client and later session, and overrides
     `AHK_MCP_TOOLSETS`. Undo with `{"action":"disable_toolset","toolset":"uia"}`
     or `{"action":"reset_toolsets"}`.

   Then load all six schemas in one ToolSearch call:
   `select:mcp__ahk__uia_windows,mcp__ahk__uia_tree,mcp__ahk__uia_find,mcp__ahk__uia_element,mcp__ahk__uia_under_cursor,mcp__ahk__uia_highlight`.
   If they still do not appear, the user must reconnect the server (`/mcp`)
   or start a new session.
2. **Is the server on the fork?** Every uia_* call runs an inspector script
   with the engine the `ahk` server resolves: env `AHK_PATH_WIN`, then
   `AHK_PATH`. Both take precedence over `AHK_Config` `ahkPath`. The inspector
   needs this fork (it calls `Print()`), and stock AutoHotkey fails on it.
   The symptom is that `uia_windows`, which touches no app UI, fails with
   `INSPECTOR_TIMEOUT` ("did not respond within 20000ms"),
   `INSPECTOR_NO_OUTPUT`, `INSPECTOR_PARSE_ERROR` or `AHK_VERSION_MISMATCH`.
   Stop retrying and tell the user: "The `ahk` MCP server runs the UIA
   inspector with stock AutoHotkey. Point `AHK_PATH` (and `AHK_PATH_WIN` if
   set) in its user-level registration at the absolute path of this repo's
   `bin\AutoHotkey64Console.exe`, then restart the server." That is user-wide
   config, so never edit it yourself.
3. **No `ahk` server connected?** Say so. Do not guess selectors instead.

## The funnel (do not skip steps)

1. **uia_windows** `{filter?}` lists top-level windows, most recently active
   first, with `hwnd`. `filter` is a substring of the title or process name.
   Minimized or cloaked windows have an empty tree (`WINDOW_SUSPENDED`), so ask
   the user to restore them. Re-list after ANY app restart: hwnds go stale and
   paths survive.
   Or use **uia_under_cursor** `{delayMs: 3000}` when the user can point at
   the control (`delayMs` is 0-10000, default 0). It is the fastest route in
   custom-drawn UIs, and it returns the leaf with its path, its snippet and
   the ancestor chain.
2. **uia_tree** `{hwnd | titleQuery, depth?, filter?, maxNodes?, fromPath?}`
   shows what the window actually contains.
   - `titleQuery` is a case-insensitive title substring. It replaces `hwnd`
     in tree, find, element and highlight, and is used only when `hwnd` is
     omitted.
   - `depth` is 1-30, default 4. Electron/WebView2 content needs 10-14.
   - `filter` is `"interactive"` (the default) or `"all"`. Use `"all"` when a
     static label or text is the target.
   - `maxNodes` is 1-2000, default 200. Output is also capped at 40 KB.
   - `fromPath` expands a collapsed or truncated subtree, using the value
     printed after `fromPath=`.
3. **uia_find** `{hwnd | titleQuery, query, controlType?, maxResults?}` matches
   `query` (required) against Name and AutomationId. Exact beats prefix beats
   substring, and `maxResults` defaults to 10. Each match carries a `path` and
   a paste-ready snippet that was executed and confirmed to resolve back to
   that element.
4. **uia_element** `{hwnd | titleQuery, path}` (or `automationId` / `name`,
   narrowed by `controlType`) dumps one element: rect, enabled/offscreen, and
   every supported pattern with its live state (Invoke, Value, Toggle,
   SelectionItem, ExpandCollapse, Scroll, LegacyIAccessible). Confirm that the
   pattern you need is there BEFORE writing automation.
5. **uia_highlight** (the same selectors, plus `durationMs`) draws a
   click-through border as the last check before committing a selector.
   `durationMs` is 100-15000, default 2000, and the call blocks for that long,
   so keep it short.

## Paths

- A path is a chain of segments joined by `/`. A segment is a control type
  with an optional `#AutomationId`, `$ClassName` or `"Name"`, plus an optional
  `:N` index, for example `Pane$RootView/Pane/Document/Button"Save"`. A path
  survives an app restart; hwnds and RuntimeIds do not.
- In compact lines (`ControlType "Name" #Id $Class {flags} @path`) the path
  follows the ` @` marker. These are `uia_tree` lines and the ancestor lines
  from `uia_under_cursor`. Pass the path WITHOUT the `@`, because a leading
  `@` fails with `BAD_PATH`. Prefer the separate `path` field that uia_find,
  uia_element and uia_under_cursor return, which has no `@`.

## Acting

The script shape below is only an outline: paste the real snippet in
unchanged.

```autohotkey
#Include <UIA>
; Verified snippet from uia_find / uia_element / uia_under_cursor, pasted unchanged:
hwnd := WinExist("Untitled - Notepad ahk_exe notepad.exe")
el := UIA.ElementFromHandle(hwnd).FindElement({A: "SaveButton"})
; Act through a pattern uia_element reported as supported:
el.Invoke()
Print("invoked {}", el.Name)
```

- **Library.** Snippets need the alpha.30-compatible UIA-v2 fork (its header
  reads `UIA-v2, AutoHotkey v2.1-alpha.30 build`). The inspector uses the same
  library, at `scripts\UIA.ahk` in the ahk-mcp checkout. Upstream UIA-v2
  fails at runtime on this engine.
- **Finding the library.** `#Include <UIA>` resolves only from these folders:
  - `<script dir>\Lib`
  - `%A_MyDocuments%\AutoHotkey\Lib`. A_MyDocuments can be redirected to
    OneDrive, so a copy in a plain `Documents` folder may not be found.
  - `<engine dir>\Lib`

  Otherwise use an absolute `#Include "...\UIA.ahk"`. Ask the user if you
  cannot find the library.
- **Validate first.** `check` prints `CHECK PASS` with exit code 0. Exit 13
  with `Script library not found` or `cannot be opened` means the include
  did not resolve.
- **Run with the fork engine.**
  - Preferred: `mcp__ahk-mcp__run {"file": "<absolute path>"}` on the project
    server. It runs `/Headless /Diag=json run` and returns `exitCode`,
    `stdout` (the `Print` output), `stderr` and `diagnostics`. The default
    timeout is 30 s, and `timeout_ms` goes up to 600000. If that server
    lists no `run` tool, it was probably started from an older `.mcp.json`
    or engine. Ask the user to reconnect it (`/mcp`), and use the CLI forms
    below meanwhile.
  - Git Bash (the Bash tool), from the repo root:
    `./bin/AutoHotkey64Console.exe check "$(cygpath -w "$f")"`, then
    `./bin/AutoHotkey64Console.exe --headless run "$(cygpath -w "$f")"`.
    Git Bash rewrites bare `/Flag` arguments into paths. Use the `--headless`
    and `--diag=json` aliases, or `//Flag`.
  - PowerShell: `& .\bin\AutoHotkey64Console.exe /Headless run $f; $LASTEXITCODE`.
  - Exit codes are 0 for success, 12 for a parse error, and 10 for an
    uncaught runtime error. For example, UIA throws `TargetError` with
    `No matching window found` or `An element matching the condition was not
    found`.
  - Do not use `mcp__ahk__AHK_Run` unless you pass `ahkPath` as the absolute
    path of `bin\AutoHotkey64Console.exe`. Without it, AHK_Run uses the
    server's `AHK_PATH`, which may be stock AutoHotkey without `Print`.
- **The script drives the real desktop.** There is no headless mode for UI
  automation, and `/Headless` only turns error dialogs into stderr text.
  - Never use `MsgBox`, `InputBox` or `Gui`, because they block until the
    timeout. Report with `Print()`.
  - Confirm with the user before any action that sends, deletes, submits or
    buys something.
  - `el.Click()` with no argument tries the Invoke, Toggle, ExpandCollapse,
    SelectionItem and then LegacyIAccessible patterns. `el.Click("left")`
    moves the real mouse.
- **Close the loop.** After the action, call `uia_element` on the same path
  again and check the state change (Toggle state, Value, and so on).
- **Write it in AHK v2.** Use parentheses on every call and `:=` for
  assignment.

## Rules

- Never guess or hand-build a `path` or selector. Use only values returned by
  `uia_tree`, `uia_find`, `uia_element` or `uia_under_cursor`, with the tree
  line's `@` stripped. If a match shows `(no verified selector)`, inspect it
  with `uia_element` rather than writing one by hand.
- An hwnd from an earlier turn plus a restarted app means the wrong window.
  Re-list, or use `titleQuery`.
- Prefer AutomationId over Name, since Name changes with localization and
  renames.
- Nothing found? Widen the search before concluding the control does not
  exist: raise `uia_tree` `depth` or `maxNodes`, switch to `filter: "all"`,
  expand with `fromPath`, or ask the user to point at it with
  `uia_under_cursor`.
