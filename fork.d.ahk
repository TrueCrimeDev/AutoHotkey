;
; fork.d.ahk — LSP declarations for this fork's additions on top of v2.1-alpha.29.
;
; Drop this file in the workspace root and the thqby AHK v2 LSP will pick it up
; automatically (it auto-scans *.d.ahk files in the workspace). IntelliSense,
; hover help, and signature help will then know about Eval(), Print(), and
; SyntaxError exactly as if they were part of the bundled declarations.
;
; If the LSP doesn't auto-discover it, in VSCode open Settings (Ctrl+,), search
; for "AutoHotkey2.Files" and add the path to this file under
; `AutoHotkey2.Files.ScanInclude` (or the equivalent in your version).
;
; Each declaration mirrors the conventions used by the upstream ahk2.d.ahk so
; the LSP processes them identically.
;

;@region Functions

/**
 * Evaluates an AutoHotkey expression string in the caller's scope and returns the result.
 *
 * Gated: the BIF throws "Eval is disabled" unless the script declares
 * `#EnableEval` or the process was launched with the `/Eval` CLI flag.
 *
 * The expression sees the caller's local variables, static / closure vars, and
 * globals (in that resolution order). Assignments inside the expression mutate
 * the caller's scope as if the expression had been typed inline.
 *
 * Throws `SyntaxError` on parse failure. Any runtime error thrown by the
 * expression propagates unchanged.
 *
 * @example
 *   #EnableEval
 *   x := 10
 *   y := 20
 *   Eval("x + y")          ; -> 30
 *   Eval("x := 99")        ; mutates caller's x
 *
 * @since 2.1-alpha.29+Console
 */
Eval(Expression) => Any

/**
 * Writes `Text` followed by a newline to stdout, UTF-8 encoded.
 *
 * No-op if the process has no console attached (e.g., a GUI app launched
 * from Explorer).
 *
 * @example
 *   Print "hello"         ; writes:  hello\n
 *   Print()               ; writes:  \n  (just a newline)
 *
 * @since 2.1-alpha.29+Console
 */
Print(Text := '') => void

;@endregion


;@region Classes

/**
 * Thrown when `Eval()` cannot parse its input expression. May also be thrown
 * by user code that wraps its own parser.
 *
 * @since 2.1-alpha.29+Console
 */
class SyntaxError extends Error {
	/**
	 * 1-based column offset of the parse error within the input string.
	 *
	 * In v1 of the fork, this is always 0 (best-effort placeholder). A future
	 * release may surface the parser's actual column position.
	 */
	Column: Integer
}

;@endregion


;
; Notes on surfaces this file CANNOT describe:
;
;   The thqby LSP only understands declarations of functions, classes, and
;   variables. Directives (`#EnableEval`, `#CrashLog`) and command-line
;   flags (`/Eval`, `/CrashLog=`, `/StdErrFile=`) live in the TextMate grammar
;   and the engine respectively — they won't appear in autocomplete from this
;   file. If you want directive highlighting, that's a separate edit to the
;   extension's `syntaxes/ahk2.tmLanguage.json` (which is also wiped on
;   extension updates).
;
;   Reference for users: see `updates.md` in this repo for the full surface.
;
