# Child process pipes

`ProcessPipe` starts a child program with UTF-8 stdin, stdout, and stderr pipes. A Windows job object manages the child process tree.

::: info Development capability
Require `features.processPipe` in `--capabilities`. This API is part of the demonstrated working-tree build.
:::

## A bounded read

```ahk
p := ProcessPipe(A_AhkPath, ["/Headless", A_ScriptDir "\child.ahk"])
try {
    Print(p.ReadLine(10))
    Print("exit={}", p.Wait(10))
} finally {
    if p.Running
        p.Kill()
}
```

The [worker recipe](/recipes/process-worker) supplies both scripts.

## Interface

| Member | Behavior |
| --- | --- |
| `ProcessPipe(command, args?, workingDir?)` | Start a program; prefer an argument array for quoting |
| `Send(text, timeout?)`, `SendLine(text, timeout?)` | Write UTF-8; the latter appends a newline |
| `ReadLine(timeout?)` | Read a stdout line without its terminator |
| `Read(timeout?)` | Read buffered stdout; optionally wait for data |
| `ReadStdErr()` | Drain buffered stderr |
| `Wait(timeout?)` | Wait for exit and return the exit code |
| `Close()` | Close **stdin**, sending EOF; it is not a process-kill method |
| `Kill()` | Terminate the job's process tree |
| `PID`, `Running`, `ExitCode`, `AtEOF` | Inspect process state |

Timeouts are in **seconds** for this API. Expiry throws `TimeoutError`. A timed-out write may already have delivered a prefix. MCP execution tool timeouts use milliseconds instead.

## Lifetime and buffering

Both output pipes are drained during waits and writes. Script timers and hotkeys can continue processing while a wait is in progress. Releasing the object closes the job and terminates remaining child processes.

Keep stdin EOF distinct from a blank output line. In a child reading a pipe, `File.AtEOF` can appear true while the pipe is momentarily empty; design an explicit message/EOF protocol and test it.

## Together with ClautoHotkey

A worker can return JSONL that an AHK test asserts against. ClautoHotkey can then validate the edit and run the test through the same engine. Its dry-run shim does not establish safety for arbitrary ProcessPipe children; keep demonstration commands controlled.
