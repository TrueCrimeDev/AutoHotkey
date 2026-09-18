# Eval & the REPL

`Eval` evaluates an AHK expression in the caller's live scope. The REPL keeps that state across multiple inputs.

## Opt into Eval

```ahk
#Requires AutoHotkey v2.1-alpha.31
#EnableEval
count := 21
Print(Eval("count * 2"))
```

Expected output: `42`. Enable evaluation with `#EnableEval` or the `/Eval` launch flag. Invalid expressions throw `SyntaxError`; unresolved identifiers can throw `UnsetError`. Evaluation can call functions and mutate state, so it is code execution, not a sandbox for untrusted expressions.

## Explore interactively

```text
ahk repl
>>> value := 10
10
>>> value * 4
40
>>> .help
>>> .exit
```

Only `.help` and `.exit` are documented meta-commands here. `repl script.ahk` runs the script's auto-execute section before opening a session against its state. Timers and GUI events can continue running.

## Machine-readable sessions

```powershell
"value := 21`nvalue * 2`n.exit" | ahk /Diag=json repl
```

JSON mode emits result records on stdout, including recoverable failures, blank lines, and meta-commands. Ordinary script output is redirected to stderr in this mode so it does not break result framing. Explicit `ExitApp` or a fatal process failure can end the session before a reply.

## In ClautoHotkey

Use `/ahk-eval` for REPL-focused work. Ask for bounded expressions and preserved stdout/stderr. A session makes exploratory work fast; a saved assertion test makes the result repeatable.
