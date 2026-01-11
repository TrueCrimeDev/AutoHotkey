#Requires AutoHotkey v2.1-alpha.17

; DebuggerInterceptor Initialization Script
; Quick setup to enable comprehensive error logging and monitoring in any AHK script

; Import the logger and viewer classes
#Include ErrorLogger.ahk
#Include LogViewer.ahk

; Global instance for access from anywhere
global DebugInterceptor := {
    logger: "",
    viewer: ""
}

; Initialize the error interceptor system
InitializeDebuggerInterceptor(autoShowTestGui := true) {
    global DebugInterceptor

    ; Create and initialize the ErrorLogger instance
    DebugInterceptor.logger := ErrorLogger()

    ; Register hotkey to show log viewer (Ctrl+Alt+L)
    Hotkey("^!l", ShowLogViewer)

    if (autoShowTestGui)
        DebugInterceptor.logger.ShowTestGui()

    return DebugInterceptor.logger
}

; Function to show the log viewer
ShowLogViewer(*) {
    if (DebugInterceptor.logger) {
        if (!DebugInterceptor.viewer || !DebugInterceptor.viewer.gui.Hwnd)
            DebugInterceptor.viewer := LogViewer()

        DebugInterceptor.viewer.Show()
    }
}

; Function to log a message (shorthand)
DebugLog(message) {
    if (DebugInterceptor.logger)
        DebugInterceptor.logger.LogInfo(message)
}

; Function to log an error (shorthand)
DebugError(message, exception := "") {
    if (DebugInterceptor.logger)
        DebugInterceptor.logger.LogError(message, exception)
}

; Function to log a warning (shorthand)
DebugWarning(message) {
    if (DebugInterceptor.logger)
        DebugInterceptor.logger.LogWarning(message)
}

; Configure the interceptor settings
ConfigureInterceptor(settings := Map()) {
    global DebugInterceptor

    ; Apply any custom settings
    for key, value in settings
        if (ErrorLogger.Config.Has(key))
            ErrorLogger.Config[key] := value

    return true
}

; Quick example usage (remove if not needed)
; InitializeDebuggerInterceptor()
