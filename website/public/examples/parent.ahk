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
