/*
log_output.ahk — Structured log output for VS Code Output Colorizer
Format: [TIMESTAMP] LEVEL message
*/
#Requires AutoHotkey v2.0

stdout := FileOpen("*", "w", "UTF-8")

Log(level, msg, extra?) {
    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss.") . Format("{:03}", A_MSec)
    line := Format("[{}] {:5} {}", ts, level, msg)
    if IsSet(extra)
        line .= " | " extra
    stdout.Write(line "`n")
}

Log("INFO",  "Application starting")
Log("INFO",  "Loading config", "path=settings.ini")
Log("DEBUG", "Parsed 12 key-value pairs")
Log("INFO",  "Initializing GUI subsystem")
Log("WARN",  "Monitor DPI scaling >150%, layout may shift", "dpi=175")
Log("INFO",  "Registering hotkeys")
Log("DEBUG", "Bound Ctrl+Shift+R to ReloadHandler")
Log("DEBUG", "Bound F12 to ToggleOverlay")
Log("INFO",  "Connecting to WebSocket", "url=ws://localhost:9000")
Log("WARN",  "Connection timeout, retrying", "attempt=1 timeout=3000ms")
Log("INFO",  "Connected to WebSocket")
Log("INFO",  "Ready — 3 hotkeys active")

; Simulate some runtime events
Log("DEBUG", "Hotkey fired: Ctrl+Shift+R")
Log("INFO",  "Script reloaded in 42ms")
Log("DEBUG", "Hotkey fired: F12")
Log("INFO",  "Overlay toggled", "visible=true")
Log("WARN",  "Audio device changed mid-stream", "device=Speakers (Realtek)")
Log("ERROR", "File not found", "path=data\cache.json errno=2")
Log("INFO",  "Recreated cache file")
Log("DEBUG", "GC freed 14 objects, 2.3KB")
Log("ERROR", "DllCall failed", "func=SetWindowCompositionAttribute hr=0x80070057")
Log("WARN",  "Falling back to basic transparency")
Log("INFO",  "Shutdown requested")
Log("INFO",  "Released 2 contexts, closed 1 socket")
Log("INFO",  "Exit code 0")
