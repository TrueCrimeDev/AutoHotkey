# Console Mirror for Main Window Views

**Date:** 2026-06-10
**Status:** Approved

## Problem

The fork's console build (`bin\AutoHotkey64.exe`, "+Console") prints `Print()` output
to the terminal, but `KeyHistory()`, `ListLines()`, `ListVars()`, and `ListHotkeys()`
still open the GUI main window. When running scripts from the VS Code terminal, that
information should land in the console like everything else.

## Behavior

- When a script explicitly calls `KeyHistory()`, `ListLines()`, `ListVars()`, or
  `ListHotkeys()` **and stdout is attached** (console build run from a terminal, or
  output redirected), the exact text that would fill the main-window edit control is
  written to stdout instead, and the GUI window is not shown or focused.
- With no stdout attached (script launched by double-click), behavior is unchanged:
  the GUI main window pops up as today.
- GUI-originated paths are unchanged in all cases: the tray menu, the main window's
  View menu, and the Refresh action still drive the GUI window. These callers reach
  `ShowMainWindow()` with `aRestricted = true`, which is the discriminator.
- The `g_AllowMainWindow` restriction logic is untouched.

## Implementation

Three files, all in `source/`:

1. **`error.cpp`** — `PrintWideLine()` (the UTF-8 stdout writer used by `Print()`):
   - Remove `static` so `ShowMainWindow` can reuse it.
   - Add a heap fallback for large payloads. The main-window buffer is up to 64K
     `TCHAR`s (~192 KB as UTF-8); `_alloca` of that on top of `ShowMainWindow`'s
     existing 128 KB stack buffer risks stack overflow. Use `_alloca` below a 16 KB
     threshold, `malloc`/`free` above it.
2. **`script.h`** — declare `void PrintWideLine(LPCTSTR text, int wlen);`
3. **`script2.cpp`** — in `ShowMainWindow()` (~line 798), after `buf_temp` is built
   and `current_mode` is updated, insert:
   - If `!aRestricted && aMode != MAIN_MODE_NO_CHANGE` and
     `GetStdHandle(STD_OUTPUT_HANDLE)` is a valid handle → `PrintWideLine(buf_temp, ...)`
     and `return OK` before the `WM_SETTEXT` / `ShowWindow` / `SetForegroundWindow`
     block. The edit control is intentionally not updated in this path; if the window
     is later opened from the tray, Refresh regenerates the view from `current_mode`.

`aRestricted == false` only for the four explicit script BIFs, so this cleanly
separates script calls (mirror to console) from GUI/tray interactions (show window).

## Testing

- `tests/` script calling each of the four BIFs, run via
  `bin_dev\AutoHotkey64.exe script.ahk` from a terminal: all four dumps appear on
  stdout, no window appears.
- Same script launched without a console: main window appears as before (manual check).
- `Print()` regression: still prints normally (it shares `PrintWideLine`).
- KeyHistory dump exceeds any small-buffer threshold only in extreme cases, but
  `ListVars`/`ListLines` on a large script exercises the heap path (>16 KB).
