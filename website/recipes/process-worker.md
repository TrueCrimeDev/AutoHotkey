# A process worker

This example uses the same verified engine for parent and child. It starts no third-party service and needs the development `processPipe` capability.

## Child: `worker.ahk`

```ahk
#Requires AutoHotkey v2.1-alpha.31
Print("worker-ready")
Print(JSON.Stringify({answer: 42}))
```

## Parent: `parent.ahk`

```ahk
#Requires AutoHotkey v2.1-alpha.31
p := ProcessPipe(A_AhkPath, ["/Headless", A_ScriptDir "\worker.ahk"])
try {
    if p.ReadLine(10) != "worker-ready"
        throw Error("Unexpected worker handshake")
    reply := JSON.Parse(p.ReadLine(10))
    if reply["answer"] != 42
        throw Error("Unexpected worker answer")
    if p.Wait(10) != 0
        throw Error("Worker failed")
    if p.ReadStdErr() != ""
        throw Error("Worker wrote stderr")
    Print("PASS: worker returned 42")
} finally {
    if p.Running
        p.Kill()
}
```

## Run it as a test

```powershell
ahk /Headless /Diag=json test .\parent.ahk
```

Expected output: `PASS: worker returned 42`, exit `0`. Both scripts must be in the same directory. Timeouts are bounded at ten seconds; the finally block terminates a still-running worker.

ClautoHotkey can validate the parent edit, but a dry-run shim does not intercept every child-process path. This intentionally executes a known local child.

Download [parent.ahk](/examples/parent.ahk) and [worker.ahk](/examples/worker.ahk). See [ProcessPipe reference](/console/process-pipe) for stdin writing, EOF, and larger output considerations.
