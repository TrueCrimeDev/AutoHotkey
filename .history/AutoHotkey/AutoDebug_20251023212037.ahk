#Requires AutoHotkey v2.0
; ============================================================================
; AutoDebug.ahk
; Transparent wrapper launcher for debugging scripts without modification
; ============================================================================
; Description: Launches target script with DebugClient pre-injected, enabling
;              error capture without modifying the original script file.
; Usage: AutoDebug.ahk <TargetScript.ahk> [arguments]
; Example: AutoDebug.ahk MyScript.ahk --test-mode
; ============================================================================

; ============================================================================
; CONFIGURATION
; ============================================================================
class AutoDebugConfig {
    static tempDir := A_Temp "\AutoDebug"
    static keepTempFiles := false  ; Set to true for debugging
    static showLaunchNotification := true
}

; ============================================================================
; MAIN LOGIC
; ============================================================================

; Check arguments
if (A_Args.Length < 1) {
    ShowUsage()
    ExitApp(1)
}

targetScript := A_Args[1]

; Validate target script exists
if (!FileExist(targetScript)) {
    MsgBox("Target script not found:`n`n" targetScript, "AutoDebug Error", "16")
    ExitApp(1)
}

; Get absolute path
targetScript := GetAbsolutePath(targetScript)

; Get any additional arguments to pass through
scriptArgs := ""
if (A_Args.Length > 1) {
    for i, arg in A_Args {
        if (i > 1) {  ; Skip first arg (target script)
            scriptArgs .= ' "' arg '"'
        }
    }
}

; Create temp directory
if (!DirExist(AutoDebugConfig.tempDir)) {
    DirCreate(AutoDebugConfig.tempDir)
}

; Generate temp wrapper script
tempScript := GenerateWrapperScript(targetScript)

; Show notification
if (AutoDebugConfig.showLaunchNotification) {
    TrayTip("AutoDebug Launcher",
            "Launching with debug client:`n" GetScriptName(targetScript),
            "1")
}

; Launch wrapper script
try {
    if (scriptArgs) {
        Run('"' A_AhkPath '" "' tempScript '" ' scriptArgs)
    } else {
        Run('"' A_AhkPath '" "' tempScript '"')
    }

    ; Wait a moment for script to start
    Sleep(500)

    ; Cleanup temp file (unless configured to keep)
    if (!AutoDebugConfig.keepTempFiles) {
        SetTimer(() => CleanupTempFile(tempScript), -5000)  ; Delete after 5s
    }

} catch Error as err {
    MsgBox("Failed to launch script:`n" err.Message, "AutoDebug Error", "16")
    ExitApp(1)
}

ExitApp(0)

; ============================================================================
; FUNCTIONS
; ============================================================================

/**
 * Generate temporary wrapper script with DebugClient injected
 */
GenerateWrapperScript(targetPath) {
    ; Get target script name for unique temp file
    SplitPath(targetPath, &targetName)
    timestamp := FormatTime(, "yyyyMMdd_HHmmss")
    tempScript := AutoDebugConfig.tempDir "\_debug_" timestamp "_" targetName

    ; Get paths
    debugClientPath := A_ScriptDir "\DebugClient.ahk"

    ; Verify DebugClient exists
    if (!FileExist(debugClientPath)) {
        MsgBox("DebugClient.ahk not found in:`n" A_ScriptDir
               . "`n`nPlease ensure DebugClient.ahk is in the same directory as AutoDebug.ahk",
               "AutoDebug Error", "16")
        ExitApp(1)
    }

    ; Build wrapper script content
    wrapper := "#Requires AutoHotkey v2.0`n"
    wrapper .= "; Auto-generated wrapper by AutoDebug.ahk`n"
    wrapper .= "; Timestamp: " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"
    wrapper .= "; Target: " targetPath "`n`n"

    ; Include DebugClient FIRST (before target script)
    wrapper .= "; Include debug client for error reporting`n"
    wrapper .= "#Include " debugClientPath "`n`n"

    ; Include target script
    wrapper .= "; Include target script`n"
    wrapper .= "#Include " targetPath "`n"

    ; Write wrapper to temp file
    try {
        FileDelete(tempScript)
    }
    FileAppend(wrapper, tempScript, "UTF-8")

    return tempScript
}

/**
 * Show usage instructions
 */
ShowUsage() {
    usage := "╔════════════════════════════════════════════════════════╗`n"
    usage .= "║              AutoDebug - Usage Instructions            ║`n"
    usage .= "╚════════════════════════════════════════════════════════╝`n`n"
    usage .= "USAGE:`n"
    usage .= "    AutoDebug.ahk <TargetScript.ahk> [arguments]`n`n"
    usage .= "DESCRIPTION:`n"
    usage .= "    Launches target script with debug client injected,`n"
    usage .= "    enabling automatic error reporting to GlobalDebugServer`n"
    usage .= "    without modifying the original script file.`n`n"
    usage .= "EXAMPLES:`n"
    usage .= "    AutoDebug.ahk MyScript.ahk`n"
    usage .= "    AutoDebug.ahk C:\Scripts\Test.ahk --verbose`n`n"
    usage .= "REQUIREMENTS:`n"
    usage .= "    1. GlobalDebugServer.ahk must be running`n"
    usage .= "    2. DebugClient.ahk must be in same directory as AutoDebug.ahk`n"
    usage .= "    3. Target script must be a valid AHK v2 script`n`n"
    usage .= "NOTES:`n"
    usage .= "    - Creates temporary wrapper in: " AutoDebugConfig.tempDir "`n"
    usage .= "    - Wrapper is deleted after 5 seconds`n"
    usage .= "    - All arguments are passed to target script`n"

    MsgBox(usage, "AutoDebug - Usage", "i")
}

/**
 * Get absolute path from relative path
 */
GetAbsolutePath(path) {
    ; If already absolute, return as-is
    if (RegExMatch(path, "^[A-Z]:|^\\\\", )) {
        return path
    }

    ; Convert relative to absolute
    Loop Files, path {
        return A_LoopFileFullPath
    }

    ; If not found, try relative to A_WorkingDir
    fullPath := A_WorkingDir "\" path
    if (FileExist(fullPath)) {
        Loop Files, fullPath {
            return A_LoopFileFullPath
        }
    }

    ; Return original if can't resolve
    return path
}

/**
 * Extract script name from full path
 */
GetScriptName(path) {
    SplitPath(path, &name)
    return name
}

/**
 * Cleanup temporary wrapper file
 */
CleanupTempFile(tempScript) {
    try {
        if (FileExist(tempScript)) {
            FileDelete(tempScript)
        }
    }
}

; ============================================================================
; NOTES
; ============================================================================
/*
    How This Works:

    1. User runs: AutoDebug.ahk TargetScript.ahk
    2. AutoDebug creates a temporary wrapper script:
       ┌─────────────────────────────────────┐
       │ #Requires AutoHotkey v2.0           │
       │ #Include DebugClient.ahk            │ ← Injected
       │ #Include TargetScript.ahk           │ ← Original script
       └─────────────────────────────────────┘
    3. Wrapper is executed via AutoHotkey64.exe
    4. DebugClient initializes and registers OnError() hook
    5. TargetScript runs normally but errors are captured
    6. Errors are sent to GlobalDebugServer via TCP
    7. Temp file is deleted after 5 seconds

    Advantages:
    - Zero modification to original script
    - Transparent to end user
    - Can be used with third-party scripts
    - Works with any AHK v2 script
    - Arguments are passed through correctly

    Limitations:
    - Requires wrapper launcher (can't double-click .ahk directly)
    - Creates temporary file (cleaned up automatically)
    - Requires GlobalDebugServer to be running

    Alternative Usage:
    - Create batch files for common scripts:
      debug_myscript.bat:
        @echo off
        AutoDebug.ahk MyScript.ahk %*

    - Then users can run: debug_myscript.bat
*/
