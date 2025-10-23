; ==================================================================================
; RunWithErrorHandler.ahk
; ==================================================================================
; Wrapper script that runs any AHK v2 script with automatic error interception
;
; Usage:
;   AutoHotkey64.exe RunWithErrorHandler.ahk "C:\Path\To\YourScript.ahk"
;
; Or create a shortcut/batch file for convenience:
;   @echo off
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "C:\Path\RunWithErrorHandler.ahk" %*
; ==================================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off  ; Allow multiple instances for different scripts

; ==================================================================================
; Configuration
; ==================================================================================
global ERROR_HANDLER_ENABLED := true
global ERROR_LOGGING_ENABLED := true

; ==================================================================================
; Error Handler Setup
; ==================================================================================
if (ERROR_HANDLER_ENABLED) {
    ; Include the error interceptor
    #Include ErrorInterceptor.ahk

    ; Optionally modify configuration
    ErrorConfig.enableLogging := ERROR_LOGGING_ENABLED
    ErrorConfig.logDirectory := A_ScriptDir "\logs\wrapped_scripts"
}

; ==================================================================================
; Command Line Argument Processing
; ==================================================================================
if (A_Args.Length == 0) {
    MsgBox(
        "Error Handler Wrapper for AutoHotkey v2`n`n" .
        "Usage: RunWithErrorHandler.ahk <script_path> [args...]`n`n" .
        "Examples:`n" .
        "  RunWithErrorHandler.ahk MyScript.ahk`n" .
        "  RunWithErrorHandler.ahk C:\Scripts\MyScript.ahk arg1 arg2`n`n" .
        "This wrapper will run the specified script with automatic error interception.",
        "RunWithErrorHandler", "Icon!"
    )
    ExitApp(1)
}

; Get target script path
targetScript := A_Args[1]

; Build absolute path if relative
if (!InStr(targetScript, ":\") && !InStr(targetScript, "\\")) {
    targetScript := A_WorkingDir "\" targetScript
}

; Verify script exists
if (!FileExist(targetScript)) {
    MsgBox(
        "Script not found: " . targetScript . "`n`n" .
        "Working Directory: " . A_WorkingDir,
        "Error", "Icon! T30"
    )
    ExitApp(1)
}

; Update A_Args to pass remaining arguments to target script
; (Remove the script path, leaving only user arguments)
if (A_Args.Length > 1) {
    global A_Args := A_Args.Clone()
    A_Args.RemoveAt(1)
} else {
    global A_Args := []
}

; ==================================================================================
; Execute Target Script
; ==================================================================================
try {
    ; Change working directory to target script's location
    SetWorkingDir(SplitPath(targetScript,,&scriptDir))

    ; Include and run the target script
    ; Note: This executes the script in the same process
    #Include %targetScript%

} catch Error as err {
    ; This catch block handles errors during script inclusion
    ; Runtime errors in the included script are handled by ErrorInterceptor
    MsgBox(
        "Failed to load target script:`n`n" .
        "Error: " . err.Message . "`n" .
        "File: " . targetScript,
        "Wrapper Error", "Icon! T30"
    )
    ExitApp(1)
}
