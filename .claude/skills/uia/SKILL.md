---
name: uia
description: Use before any Windows UI inspection or automation with the mcp__ahk__uia_* tools — enforces the windows → tree → find → element → highlight funnel and the act-via-generated-snippet rule.
---

# UIA Funnel — inspect first, act through the engine

The `mcp__ahk__uia_*` tools are READ-ONLY. Automation happens by taking the
verified AHK snippet a tool returns and running it with the fork engine
(`mcp__ahk__AHK_Run` or `bin\AutoHotkey64.exe /ErrorStdOut script.ahk`).

## The funnel (don't skip steps)

1. **uia_windows** — list top-level windows, get `hwnd`.
   Re-list after ANY app restart: hwnds go stale, `@path`s survive.
2. **uia_tree** `{hwnd, depth}` — see what the window actually contains.
   Default depth 4 misses Electron/WebView2 content — use `depth: 10–14`
   there, and `fromPath` to expand a stubbed subtree. `filter: "all"` when a
   static label/text is the target.
3. **uia_find** `{hwnd, query, controlType?}` — fuzzy-match by Name or
   AutomationId. Every match ships a durable `@path` plus a paste-ready AHK
   v2 snippet already executed and confirmed to resolve to that element.
4. **uia_element** `{hwnd, path}` — confirm the control exposes the pattern
   you need (Invoke / Value / Toggle / SelectionItem / ExpandCollapse)
   BEFORE writing automation against it.
5. **uia_highlight** — visual confirmation, as the last step before
   committing a selector to a script.

## Acting

- Put the returned snippet in a script and run it headless with `AHK_Run`
  (or the engine CLI). Parenthesize every call; `:=` for assignment.
- Close the loop: after the action, call `uia_element` on the same path
  again and assert the state change (Toggle state, Value, etc.).

## Rules

- Never guess or hand-build a `@path` — only use paths returned by
  `uia_tree` / `uia_find`.
- An hwnd from an earlier turn + a restarted app = the wrong window. Re-list.
- Prefer AutomationId over Name (Name breaks on localization / renames).
- Nothing found? Widen: raise `uia_tree` depth / `maxNodes`, or switch to
  `filter: "all"` — before concluding the control doesn't exist.
