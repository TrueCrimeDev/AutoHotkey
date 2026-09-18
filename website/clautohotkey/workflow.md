# The edit → verify loop

The plugin connects Claude Code's file-edit tools to the configured AHK interpreter. Keep **automatic hooks**, **grading gates**, and **runtime tests** distinct; they answer different questions.

<WorkflowDemo />

## Before the edit

The `inject-rules.sh` PreToolUse hook loads matching AHK rules for Write/Edit. This gives Claude relevant constraints before it changes an `.ahk` file: target version, syntax, demo location, GUI guidance, or library conventions.

## After the edit

`ahk-post-edit.sh` receives the tool's file path and performs validation. With `RUNTIME_PROBE=1`, selected standalone scripts also receive a bounded runtime probe. Other hooks handle optional reloads and error logging.

A PostToolUse failure occurs **after the filesystem write**. It reports an invalid edit and feeds the error back into the next step; it does not undo the write or prove an invalid file never existed.

## Test the integration deliberately

In a disposable directory, ask for a tiny malformed script, observe the syntax failure, then repair it and observe success. Use a harmless fixture. Keep runtime probes disabled for scripts that can change applications or external state unless that behavior is part of your test.

## A useful task request

```text
Create Demo/json_summary.ahk for the configured Console build.
Use the plugin's Write/Edit workflow so the real validation hooks run.
Add assertions for expected output and invalid JSON input.
Report the interpreter, commands, exit codes, and untested scope.
Keep the work in this disposable demo folder.
```

## Finish at the right boundary

- Syntax accepted: source parses under the configured build.
- Probe completed: the selected bounded execution did not reveal a failure.
- Assertions passed: those behaviors matched their expected results.
- Live app verified: actual GUI/input/application outcomes were observed.

The [gallery](/showcase) demonstrates the first three categories for controlled console fixtures. It does not certify arbitrary desktop automation.
