#Requires AutoHotkey v2.0
#Include Lib\child_process.ahk
#Include DebugClient.ahk

if (A_Args.Length < 1) {
    MsgBox("Usage: AutoDebugAsync.ahk <TargetScript>")
    ExitApp
}

targetScript := A_Args[1]
if (!FileExist(targetScript)) {
    MsgBox("File not found: " targetScript)
    ExitApp
}

; Initialize DebugClient to communicate with the server
DebugClient.Initialize()

; Launch the target script with /ErrorStdOut to capture errors in stdout/stderr
; We use the same interpreter as the current script
exePath := A_AhkPath

DebugClient.SendDebug("Starting async debug session for: " targetScript)

try {
    ; Create child process
    ; We pass /ErrorStdOut so AHK writes errors to stderr/stdout instead of showing a dialog
    proc := child_process(exePath, ["/ErrorStdOut", targetScript])
    
    ; Setup event handlers
    proc.stdout.onData := (pipe, str) => ForwardOutput("STDOUT", str)
    proc.stderr.onData := (pipe, str) => ForwardOutput("STDERR", str)
    
    ; Wait for process to exit (optional, or we can keep running)
    proc.Wait()
    
    DebugClient.SendDebug("Async session ended. Exit code: " proc.ExitCode)
    
} catch Error as err {
    DebugClient.SendDebug("Failed to launch child process: " err.Message)
}

ForwardOutput(source, text) {
    ; Trim whitespace
    text := Trim(text, " `t`r`n")
    if (text == "")
        return
        
    ; Send to server
    ; We prefix with source to distinguish
    DebugClient.SendDebug("[" source "] " text)
}
