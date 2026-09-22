#Requires AutoHotkey v2.1-alpha.31
#Include ..\Assert.ahk
; ProcessPipe: native child process with UTF-8 stdio pipes and job-object cleanup.

dir := A_Temp "\qa_pipe_" ProcessExist()
DirCreate(dir)
Write(name, src) {
    global dir
    path := dir "\" name
    FileOpen(path, "w", "UTF-8-RAW").Write(src)
    return path
}
Engine(script, args*) {
    argv := ["/Headless", "/ErrorStdOut", script]
    argv.Push(args*)
    return ProcessPipe(A_AhkPath, argv)
}

echo := Write("echo.ahk", '
(
; File.AtEOF is unreliable on a pipe (true while the pipe is momentarily empty),
; so read until ReadLine returns an empty string, which only EOF produces here.
stdin := FileOpen("*", "r", "UTF-8")
loop {
    line := stdin.ReadLine()
    if line = ""
        break
    Print("echo:{}", line)
}
ExitApp(7)
)')

; --- round trip, UTF-8, exit code, EOF -----------------------------------------
p := Engine(echo)
Assert.truthy(p.PID > 0, "PID assigned")
Assert.truthy(p.Running, "running after start")
Assert.eq(p.ExitCode, -1, "ExitCode is -1 while running")
p.SendLine("héllo 🌍 日本")
Assert.eq(p.ReadLine(5), "echo:héllo 🌍 日本", "UTF-8 round trip")
p.Send("two")
p.Send(" parts`n")
Assert.eq(p.ReadLine(5), "echo:two parts", "Send without newline accumulates")
p.Close()
Assert.eq(p.Wait(5), 7, "Wait returns the exit code")
Assert.falsy(p.Running, "not running after exit")
Assert.eq(p.ExitCode, 7, "ExitCode after exit")
Assert.eq(p.ReadLine(1), "", "ReadLine at EOF returns empty")
Assert.truthy(p.AtEOF, "AtEOF after drain")

; --- timeouts and kill --------------------------------------------------------------
p := Engine(echo)
Assert.throws(() => p.ReadLine(0.2), "ReadLine times out", "Timeout")
Assert.throws(() => p.Wait(0.2), "Wait times out", "Timeout")
Assert.truthy(p.Running, "still running after timeouts")
pid := p.PID
p.Kill()
Assert.falsy(p.Running, "killed")
Assert.falsy(ProcessExist(pid), "process gone after Kill")
Assert.eq(p.ExitCode, 1, "killed exit code")

; --- stderr and stdout are separate ---------------------------------------------------
mixed := Write("mixed.ahk", '
(
Print("out1")
FileAppend("err1``n", "**")
Print("out2")
)')
p := Engine(mixed)
Assert.eq(p.Wait(5), 0, "mixed exits 0")
Assert.eq(p.Read(), "out1`nout2`n", "stdout collected after exit")
Assert.truthy(InStr(p.ReadStdErr(), "err1"), "stderr collected separately")
Assert.eq(p.ReadStdErr(), "", "ReadStdErr drains")

; --- large output must not deadlock and UTF-8 must survive chunk boundaries ----------
big := Write("big.ahk", '
(
Loop 20000
    Print("{:05}:{}", A_Index, "é1234567890é1234567890é1234567890é1234567890é1234567890é1234567890é1234567890é123456789")
)')
p := Engine(big)
Assert.eq(p.Wait(30), 0, "2 MB producer exits while we wait")
text := p.Read()
lines := StrSplit(RTrim(text, "`n"), "`n")
Assert.eq(lines.Length, 20000, "every line arrived")
Assert.eq(lines[20000], "20000:é1234567890é1234567890é1234567890é1234567890é1234567890é1234567890é1234567890é123456789", "last line intact")
Assert.falsy(InStr(text, Chr(0xFFFD)), "no replacement chars from split UTF-8 sequences")
wide := Write("wide.ahk", '
(
s := ""
Loop 100000
    s .= "é"
Print(s)
)')
p := Engine(wide)
line := p.ReadLine(30)
Assert.eq(StrLen(line), 100000, "200 KB single line decoded across pipe chunks")
p.Wait(5)

; --- argument quoting ---------------------------------------------------------------
argsScript := Write("args.ahk", '
(
for a in A_Args
    Print("[{}]", a)
)')
p := Engine(argsScript, "a b", 'q"uote', "", "back\slash\", "tab`there")
Assert.eq(p.Wait(5), 0, "args script exits")
Assert.eq(p.Read(), "[a b]`n[q`"uote]`n[]`n[back\slash\]`n[tab`there]`n", "arguments survive quoting")

; --- raw string args and no args --------------------------------------------------------
p := ProcessPipe(A_AhkPath, '/Headless /ErrorStdOut "' argsScript '" x y')
p.Wait(5)
Assert.eq(p.Read(), "[x]`n[y]`n", "raw argument string")
p := ProcessPipe('"' A_AhkPath '" /Headless /ErrorStdOut "' argsScript '" z')
p.Wait(5)
Assert.eq(p.Read(), "[z]`n", "single command-line form")

; --- releasing the object kills the tree ------------------------------------------------
stay := Write("stay.ahk", '
(
Persistent()
SetTimer(() => 0, 1000)
)')
p := Engine(stay)
pid := p.PID
Sleep(200)
Assert.truthy(ProcessExist(pid), "persistent child alive")
p := ""
Sleep(300)
Assert.falsy(ProcessExist(pid), "child killed when the object is released")

; --- errors -----------------------------------------------------------------------------
Assert.throws(() => ProcessPipe("definitely-not-a-program-" A_TickCount ".exe"), "missing program throws OSError", "")
Assert.throws(() => ProcessPipe(""), "empty command rejected")
Assert.throws(() => ProcessPipe(A_AhkPath, {not: "array"}), "bad Args type rejected")
p := Engine(echo)
p.Close()
Assert.throws(() => p.SendLine("x"), "Send after Close throws")
p.Wait(5)

; --- Read without timeout never blocks --------------------------------------------------
p := Engine(echo)
Assert.eq(p.Read(), "", "Read() returns immediately when idle")
p.SendLine("late")
Assert.eq(p.Read(2), "echo:late`n", "Read(timeout) waits for data")
p.Kill()

; --- writes never deadlock against a child that is busy writing -------------------------------
; The child floods stdout before it reads stdin; we push 2 MB into stdin first. Without
; overlapped writes plus pumping, both sides would block on full pipes forever.
cross := Write("cross.ahk", '
(
Loop 20000
    Print("0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789")
stdin := FileOpen("*", "r", "UTF-8")
total := 0
loop {
    line := stdin.ReadLine()
    if line = ""
        break
    total += StrLen(line)
}
Print("read:{}", total)
)')
payload := ""
Loop 2000
    payload .= "abcdefghij"
p := Engine(cross)
Loop 100
    p.SendLine(payload)
p.Close()
Assert.eq(p.Wait(60), 0, "cross-flooded child exits")
out := p.Read()
Assert.truthy(InStr(out, "read:2000000"), "child received all 2 MB while flooding stdout")
Assert.eq(StrSplit(RTrim(out, "`n"), "`n").Length, 20001, "all 20000 flood lines plus the summary arrived")

; --- Send(timeout) against a child that never reads stdin -----------------------------------------
deaf := Write("deaf.ahk", '
(
Persistent()
SetTimer(() => 0, 1000)
)')
p := Engine(deaf)
Assert.noThrow(() => p.SendLine("fits in the pipe buffer", 1), "small write completes without a reader")
t0 := A_TickCount
Assert.throws(() => Send2MB(p), "2 MB write to a deaf child times out", "Timeout")
Send2MB(p) {
    global payload
    Loop 200
        p.SendLine(payload, 0.5)
}
Assert.truthy(A_TickCount - t0 < 5000, "timeout honored promptly (" (A_TickCount - t0) " ms)")
Assert.truthy(p.Running, "child survives the cancelled write")
p.Kill()

; --- output written before we start reading is not lost -------------------------------------
quick := Write("quick.ahk", '
(
Print("a")
Print("b")
Print("c")
)')
p := Engine(quick)
Sleep(400)
Assert.eq(p.ReadLine(2) p.ReadLine(2) p.ReadLine(2), "abc", "early output buffered")
Assert.eq(p.Wait(5), 0, "quick exit")

DirDelete(dir, true)
Assert.Summary()
