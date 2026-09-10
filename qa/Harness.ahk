#Requires AutoHotkey v2.1-alpha.30
; Each child runs headless inside a Windows job. Closing the job also cleans up
; descendants; launching suspended prevents a child escaping before assignment.

QaTimeoutMs() {
    value := EnvGet("AHK_QA_TIMEOUT_MS")
    if value = ""
        return 30000
    if !IsInteger(value) || value < 1 || value > 300000
        throw ValueError("AHK_QA_TIMEOUT_MS must be an integer from 1 to 300000")
    return Integer(value)
}

RunQaChild(script, args := "", timeoutMs := QaTimeoutMs()) {
    static seq := 0
    seq += 1
    tmp := A_Temp "\qa_" ProcessExist() "_" A_TickCount "_" seq ".out"
    job := 0, output := 0, input := 0, process := 0, thread := 0
    timedOut := false, code := 0, out := ""
    try {
        job := DllCall("CreateJobObjectW", "ptr", 0, "ptr", 0, "ptr")
        if !job
            throw OSError()
        limits := Buffer(A_PtrSize = 8 ? 144 : 112, 0)
        NumPut("uint", 0x2000, limits, 16) ; JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if !DllCall("SetInformationJobObject", "ptr", job, "int", 9,
            "ptr", limits, "uint", limits.Size)
            throw OSError()

        security := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
        NumPut("uint", security.Size, security)
        NumPut("int", 1, security, A_PtrSize * 2) ; inheritable stdio handles
        output := DllCall("CreateFileW", "str", tmp, "uint", 0x40000000,
            "uint", 1, "ptr", security, "uint", 2, "uint", 0x80, "ptr", 0, "ptr")
        if output = -1
            throw OSError()
        input := DllCall("CreateFileW", "str", "NUL", "uint", 0x80000000,
            "uint", 3, "ptr", security, "uint", 3, "uint", 0x80, "ptr", 0, "ptr")
        if input = -1
            throw OSError()

        startup := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
        NumPut("uint", startup.Size, startup)
        NumPut("uint", 0x101, startup, A_PtrSize = 8 ? 60 : 44)
        stdOffset := A_PtrSize = 8 ? 80 : 56
        NumPut("ptr", input, "ptr", output, "ptr", output, startup, stdOffset)
        info := Buffer(A_PtrSize * 2 + 8, 0)
        command := '"' A_AhkPath '" /Headless /ErrorStdOut "' script '" ' args
        commandBuf := Buffer((StrLen(command) + 1) * 2, 0)
        StrPut(command, commandBuf, "UTF-16")
        if !DllCall("CreateProcessW", "str", A_AhkPath, "ptr", commandBuf,
            "ptr", 0, "ptr", 0, "int", true, "uint", 0x08000004,
            "ptr", 0, "ptr", 0, "ptr", startup, "ptr", info)
            throw OSError()
        process := NumGet(info, 0, "ptr"), thread := NumGet(info, A_PtrSize, "ptr")
        if !DllCall("AssignProcessToJobObject", "ptr", job, "ptr", process)
            throw OSError()
        if DllCall("ResumeThread", "ptr", thread, "uint") = 0xFFFFFFFF
            throw OSError()
        wait := DllCall("WaitForSingleObject", "ptr", process, "uint", timeoutMs, "uint")
        if wait = 258 {
            timedOut := true
            if !DllCall("TerminateJobObject", "ptr", job, "uint", 124)
                throw OSError()
            if DllCall("WaitForSingleObject", "ptr", process, "uint", 5000, "uint") != 0
                throw Error("Timed-out child did not terminate")
        } else if wait != 0
            throw OSError()
        if !DllCall("GetExitCodeProcess", "ptr", process, "uint*", &code)
            throw OSError()
    } finally {
        ; Also handle setup failures before the child was assigned to the job.
        if process && DllCall("WaitForSingleObject", "ptr", process, "uint", 0, "uint") = 258 {
            DllCall("TerminateProcess", "ptr", process, "uint", 124)
            DllCall("WaitForSingleObject", "ptr", process, "uint", 5000)
        }
        if job
            DllCall("CloseHandle", "ptr", job)
        for handle in [thread, process, input, output]
            if handle && handle != -1
                DllCall("CloseHandle", "ptr", handle)
        if FileExist(tmp) {
            try out := FileRead(tmp, "UTF-8")
            try FileDelete(tmp)
        }
    }
    return {code: code, out: out, timedOut: timedOut, timeoutMs: timeoutMs}
}

; Tests can still inspect the exact merged output and process exit status.
RunSnippet(src, args := "") {
    static seq := 0
    seq += 1
    script := A_Temp "\qa_snip_" ProcessExist() "_" A_TickCount "_" seq ".ahk"
    try {
        FileAppend(src, script, "UTF-8")
        result := RunQaChild(script, args)
        if result.timedOut
            throw Error("QA snippet exceeded " result.timeoutMs " ms")
        return result
    } finally {
        try FileDelete(script)
    }
}

; Convenience: the raw stdout of a snippet that is expected to succeed.
SnippetOut(src) => RunSnippet(src).out
