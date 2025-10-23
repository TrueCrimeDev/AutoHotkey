; ==================================================================================
; GlobalErrorMonitor.ahk
; ==================================================================================
; Background service that monitors error logs from all scripts
; Displays notifications when errors occur in any wrapped script
;
; Usage:
;   1. Run this script in the background (starts minimized to tray)
;   2. Run other scripts using RunWithErrorHandler.ahk
;   3. This monitor will watch the log directory and alert on new errors
; ==================================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; ==================================================================================
; Configuration
; ==================================================================================
class MonitorConfig {
    static logDirectory := A_ScriptDir "\logs\wrapped_scripts"
    static checkInterval := 2000  ; Check every 2 seconds
    static showNotifications := true
    static maxNotificationsPerMinute := 5
    static notificationTimeout := 10  ; Seconds
}

; ==================================================================================
; Tray Icon Setup
; ==================================================================================
TraySetIcon("imageres.dll", 234)  ; Shield icon
A_IconTip := "AHK Error Monitor - Watching for errors..."

; Add tray menu items
A_TrayMenu.Delete()
A_TrayMenu.Add("Open Log Directory", (*) => Run(MonitorConfig.logDirectory))
A_TrayMenu.Add("View Recent Errors", (*) => ShowRecentErrors())
A_TrayMenu.Add()
A_TrayMenu.Add("Pause Monitoring", (*) => ToggleMonitoring())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "View Recent Errors"

; ==================================================================================
; Global State
; ==================================================================================
global isMonitoring := true
global lastLogCheck := A_Now
global processedErrors := Map()
global recentErrors := []
global notificationCount := 0
global lastNotificationReset := A_TickCount

; ==================================================================================
; Initialize Monitor
; ==================================================================================
; Ensure log directory exists
if (!DirExist(MonitorConfig.logDirectory)) {
    DirCreate(MonitorConfig.logDirectory)
}

; Start monitoring timer
SetTimer(CheckForNewErrors, MonitorConfig.checkInterval)

; Show startup notification
TrayTip("AHK Error Monitor Started", "Monitoring: " . MonitorConfig.logDirectory, "Info")

; ==================================================================================
; Main Monitoring Function
; ==================================================================================
CheckForNewErrors() {
    global isMonitoring, lastLogCheck

    if (!isMonitoring) {
        return
    }

    ; Reset notification counter every minute
    if (A_TickCount - lastNotificationReset > 60000) {
        global notificationCount := 0
        global lastNotificationReset := A_TickCount
    }

    ; Find all log files
    Loop Files, MonitorConfig.logDirectory "\error_log_*.txt" {
        logFile := A_LoopFileFullPath

        ; Check if file was modified since last check
        if (A_LoopFileTimeModified > lastLogCheck) {
            ProcessLogFile(logFile)
        }
    }

    lastLogCheck := A_Now
}

; ==================================================================================
; Process Individual Log File
; ==================================================================================
ProcessLogFile(logPath) {
    global processedErrors, recentErrors, notificationCount

    try {
        content := FileRead(logPath)

        ; Parse error entries (separated by separator lines)
        errors := StrSplit(content, "═══════════════════════════════════════════════════════")

        for errorText in errors {
            errorText := Trim(errorText)
            if (errorText == "") {
                continue
            }

            ; Create unique hash for this error
            errorHash := GetErrorHash(errorText)

            ; Skip if already processed
            if (processedErrors.Has(errorHash)) {
                continue
            }

            ; Mark as processed
            processedErrors[errorHash] := A_Now

            ; Extract error details
            errorInfo := ParseErrorText(errorText)

            ; Store in recent errors
            recentErrors.Push(errorInfo)
            if (recentErrors.Length > 50) {  ; Keep only last 50
                recentErrors.RemoveAt(1)
            }

            ; Show notification if enabled
            if (MonitorConfig.showNotifications &&
                notificationCount < MonitorConfig.maxNotificationsPerMinute) {
                ShowErrorNotification(errorInfo)
                notificationCount++
            }
        }
    } catch Error as err {
        ; Silently handle file read errors (file might be locked)
    }
}

; ==================================================================================
; Helper Functions
; ==================================================================================
GetErrorHash(text) {
    ; Simple hash based on first 200 characters
    hashText := SubStr(text, 1, 200)
    hash := 0
    Loop Parse hashText {
        hash := (hash * 31 + Ord(A_LoopField)) & 0xFFFFFFFF
    }
    return hash
}

ParseErrorText(text) {
    info := Map()
    info["timestamp"] := A_Now
    info["fullText"] := text

    ; Extract error type
    if (RegExMatch(text, "Error Type:\s*(\w+)", &match)) {
        info["type"] := match[1]
    } else {
        info["type"] := "Unknown"
    }

    ; Extract message
    if (RegExMatch(text, "Message:\s*([^\n]+)", &match)) {
        info["message"] := Trim(match[1])
    } else {
        info["message"] := "No message"
    }

    ; Extract file/line
    if (RegExMatch(text, "File:\s*([^\n]+)", &match)) {
        info["file"] := Trim(match[1])
    } else {
        info["file"] := "Unknown"
    }

    if (RegExMatch(text, "Line:\s*(\d+)", &match)) {
        info["line"] := match[1]
    } else {
        info["line"] := "?"
    }

    return info
}

ShowErrorNotification(errorInfo) {
    title := "AHK Error: " . errorInfo["type"]
    message := errorInfo["message"] . "`n`n" .
               "File: " . SplitPath(errorInfo["file"],,, &name) . name . "`n" .
               "Line: " . errorInfo["line"]

    TrayTip(title, message, "Error", MonitorConfig.notificationTimeout)
}

ShowRecentErrors() {
    global recentErrors

    if (recentErrors.Length == 0) {
        MsgBox("No errors detected yet.", "Recent Errors", "Iconi")
        return
    }

    ; Build error list
    errorList := "Recent Errors (Last " . recentErrors.Length . "):`n`n"

    for errorInfo in recentErrors {
        errorList .= "─────────────────────────────────────`n"
        errorList .= errorInfo["type"] . ": " . errorInfo["message"] . "`n"
        errorList .= "  → " . SplitPath(errorInfo["file"],,, &name) . name . ":" . errorInfo["line"] . "`n`n"
    }

    ; Show in message box
    MsgBox(errorList, "Recent Errors", "Icon! T0")
}

ToggleMonitoring() {
    global isMonitoring
    isMonitoring := !isMonitoring

    if (isMonitoring) {
        A_TrayMenu.Rename("Resume Monitoring", "Pause Monitoring")
        A_IconTip := "AHK Error Monitor - Watching for errors..."
        TrayTip("Monitoring Resumed", "Now watching for errors", "Info")
    } else {
        A_TrayMenu.Rename("Pause Monitoring", "Resume Monitoring")
        A_IconTip := "AHK Error Monitor - Paused"
        TrayTip("Monitoring Paused", "Not watching for errors", "Info")
    }
}
