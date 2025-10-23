#Requires AutoHotkey v2.0
; ============================================================================
; GlobalDebugServer.ahk
; TCP-based global error monitoring server for AHK v2 scripts
; ============================================================================
; Description: Runs as background service, listens on TCP port for error
;              reports from instrumented scripts. Displays errors in unified
;              GUI, logs to file, sends notifications.
; Usage: Run this script in background, then run monitored scripts with
;        DebugClient.ahk included or via AutoDebug.ahk wrapper.
; ============================================================================

#SingleInstance Force

; ============================================================================
; CONFIGURATION
; ============================================================================
class ServerConfig {
    static port := 9999
    static bindAddress := "127.0.0.1"  ; localhost only (change to "0.0.0.0" for network)
    static maxConnections := 10
    static enableLogging := true
    static logDirectory := A_ScriptDir "\ErrorLogs"
    static showNotifications := true
    static maxNotificationsPerMinute := 5
    static guiUpdateInterval := 100  ; ms
}

; ============================================================================
; GLOBAL STATE
; ============================================================================
global serverSocket := 0
global clientSockets := Map()
global errorQueue := []
global errorHistory := []
global notificationCount := 0
global lastNotificationReset := A_TickCount
global isServerRunning := false
global mainGui := ""

; ============================================================================
; TRAY ICON SETUP
; ============================================================================
TraySetIcon("imageres.dll", 234)  ; Shield icon
A_IconTip := "Global Debug Server - Starting..."

A_TrayMenu.Delete()
A_TrayMenu.Add("Show Error Console", (*) => ShowMainGUI())
A_TrayMenu.Add("View Statistics", (*) => ShowStatistics())
A_TrayMenu.Add()
A_TrayMenu.Add("Clear Error History", (*) => ClearHistory())
A_TrayMenu.Add("Open Log Directory", (*) => Run(ServerConfig.logDirectory))
A_TrayMenu.Add()
A_TrayMenu.Add("Stop Server", (*) => StopServer())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show Error Console"

; ============================================================================
; SERVER CLASS
; ============================================================================
class DebugServer {
    /**
     * Initialize and start TCP server
     */
    static Start() {
        global isServerRunning, serverSocket

        ; Create log directory
        if (ServerConfig.enableLogging) {
            if (!DirExist(ServerConfig.logDirectory)) {
                DirCreate(ServerConfig.logDirectory)
            }
        }

        ; Create server socket
        try {
            serverSocket := this.CreateServerSocket(
                ServerConfig.bindAddress,
                ServerConfig.port
            )

            if (!serverSocket) {
                throw Error("Failed to create server socket")
            }

            isServerRunning := true

            ; Start accepting connections
            SetTimer(() => this.AcceptConnections(), 100)

            ; Start processing error queue
            SetTimer(() => this.ProcessErrorQueue(), ServerConfig.guiUpdateInterval)

            ; Update tray
            A_IconTip := "Global Debug Server - Running on port " ServerConfig.port
            TrayTip("Debug Server Started",
                    "Listening on " ServerConfig.bindAddress ":" ServerConfig.port,
                    "1")

            ; Create main GUI
            CreateMainGUI()

        } catch Error as err {
            MsgBox("Failed to start server:`n" err.Message, "Server Error", "16")
            ExitApp()
        }
    }

    /**
     * Create TCP server socket using WinSock
     */
    static CreateServerSocket(address, port) {
        ; Initialize WinSock
        static WSADATA_SIZE := 400
        wsaData := Buffer(WSADATA_SIZE, 0)

        if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData)) {
            return 0
        }

        ; Create socket
        static AF_INET := 2
        static SOCK_STREAM := 1
        static IPPROTO_TCP := 6

        sock := DllCall("ws2_32\socket", "Int", AF_INET, "Int", SOCK_STREAM, "Int", IPPROTO_TCP, "Ptr")

        if (sock == -1) {
            return 0
        }

        ; Set socket to non-blocking mode
        static FIONBIO := 0x8004667E
        mode := 1
        DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", FIONBIO, "UInt*", &mode)

        ; Set SO_REUSEADDR
        static SOL_SOCKET := 0xFFFF
        static SO_REUSEADDR := 0x0004
        optval := 1
        DllCall("ws2_32\setsockopt",
                "Ptr", sock,
                "Int", SOL_SOCKET,
                "Int", SO_REUSEADDR,
                "Ptr*", &optval,
                "Int", 4)

        ; Bind socket
        sockaddr := Buffer(16, 0)
        NumPut("UShort", AF_INET, sockaddr, 0)
        NumPut("UShort", DllCall("ws2_32\htons", "UShort", port, "UShort"), sockaddr, 2)

        ; Convert IP address
        if (address == "0.0.0.0") {
            NumPut("UInt", 0, sockaddr, 4)  ; INADDR_ANY
        } else {
            ipAddr := DllCall("ws2_32\inet_addr", "AStr", address, "UInt")
            NumPut("UInt", ipAddr, sockaddr, 4)
        }

        if (DllCall("ws2_32\bind", "Ptr", sock, "Ptr", sockaddr, "Int", 16)) {
            DllCall("ws2_32\closesocket", "Ptr", sock)
            return 0
        }

        ; Listen
        if (DllCall("ws2_32\listen", "Ptr", sock, "Int", ServerConfig.maxConnections)) {
            DllCall("ws2_32\closesocket", "Ptr", sock)
            return 0
        }

        return sock
    }

    /**
     * Accept new client connections
     */
    static AcceptConnections() {
        global serverSocket, clientSockets

        if (!isServerRunning || !serverSocket) {
            return
        }

        ; Try to accept connection (non-blocking)
        sockaddr := Buffer(16, 0)
        addrLen := 16

        clientSock := DllCall("ws2_32\accept",
                              "Ptr", serverSocket,
                              "Ptr", sockaddr,
                              "Int*", &addrLen,
                              "Ptr")

        if (clientSock != -1) {
            ; Got new connection
            clientSockets[clientSock] := Map(
                "socket", clientSock,
                "connected", A_Now,
                "buffer", ""
            )

            ; Start receiving data from this client
            SetTimer(() => this.ReceiveFromClient(clientSock), 50)
        }
    }

    /**
     * Receive data from connected client
     */
    static ReceiveFromClient(clientSock) {
        global clientSockets, errorQueue

        if (!clientSockets.Has(clientSock)) {
            return
        }

        ; Receive data (non-blocking)
        local buffer, bytesReceived
        buffer := Buffer(4096, 0)
        bytesReceived := DllCall("ws2_32\recv",
                                 "Ptr", clientSock,
                                 "Ptr", buffer,
                                 "Int", 4096,
                                 "Int", 0,
                                 "Int")

        if (bytesReceived > 0) {
            ; Got data
            data := StrGet(buffer, bytesReceived, "UTF-8")
            clientSockets[clientSock]["buffer"] .= data

            ; Check for complete packet (newline-delimited JSON)
            while (InStr(clientSockets[clientSock]["buffer"], "`n")) {
                pos := InStr(clientSockets[clientSock]["buffer"], "`n")
                packet := SubStr(clientSockets[clientSock]["buffer"], 1, pos - 1)
                clientSockets[clientSock]["buffer"] := SubStr(clientSockets[clientSock]["buffer"], pos + 1)

                ; Parse and queue error
                try {
                    errorData := JSON.Parse(packet)
                    errorQueue.Push(errorData)
                } catch {
                    ; Invalid JSON - ignore
                }
            }

        } else if (bytesReceived == 0) {
            ; Client disconnected
            this.DisconnectClient(clientSock)
        }
    }

    /**
     * Disconnect client and cleanup
     */
    static DisconnectClient(clientSock) {
        global clientSockets

        if (clientSockets.Has(clientSock)) {
            DllCall("ws2_32\closesocket", "Ptr", clientSock)
            clientSockets.Delete(clientSock)
        }
    }

    /**
     * Process queued errors
     */
    static ProcessErrorQueue() {
        global errorQueue, errorHistory, notificationCount, lastNotificationReset

        ; Reset notification counter every minute
        if (A_TickCount - lastNotificationReset > 60000) {
            notificationCount := 0
            lastNotificationReset := A_TickCount
        }

        while (errorQueue.Length > 0) {
            errorData := errorQueue.RemoveAt(1)

            ; Add to history
            errorHistory.Push(errorData)
            if (errorHistory.Length > 1000) {  ; Keep last 1000 errors
                errorHistory.RemoveAt(1)
            }

            ; Log to file
            if (ServerConfig.enableLogging) {
                this.LogError(errorData)
            }

            ; Update GUI
            if (mainGui) {
                UpdateErrorList(errorData)
            }

            ; Show notification
            if (ServerConfig.showNotifications &&
                notificationCount < ServerConfig.maxNotificationsPerMinute) {
                this.ShowNotification(errorData)
                notificationCount++
            }
        }
    }

    /**
     * Log error to file
     */
    static LogError(errorData) {
        try {
            logFile := ServerConfig.logDirectory
                     . "\global_error_log_"
                     . FormatTime(, "yyyy-MM-dd")
                     . ".txt"

            entry := "`n════════════════════════════════════════════════════════`n"
            entry .= "Timestamp: " errorData["timestamp"] "`n"
            entry .= "Script: " errorData["script"] " (PID: " errorData["pid"] ")`n"
            entry .= "Error Type: " errorData["error"]["type"] "`n"
            entry .= "Message: " errorData["error"]["message"] "`n"
            entry .= "File: " errorData["error"]["file"] "`n"
            entry .= "Line: " errorData["error"]["line"] "`n"

            if (errorData["error"]["what"]) {
                entry .= "What: " errorData["error"]["what"] "`n"
            }

            if (errorData["error"]["stack"]) {
                entry .= "`nStack Trace:`n" errorData["error"]["stack"] "`n"
            }

            entry .= "════════════════════════════════════════════════════════`n"

            FileAppend(entry, logFile, "UTF-8")

        } catch {
            ; Silently fail if logging fails
        }
    }

    /**
     * Show tray notification
     */
    static ShowNotification(errorData) {
        title := "AHK Error: " errorData["error"]["type"]
        message := errorData["script"] " (Line " errorData["error"]["line"] ")`n"
                 . errorData["error"]["message"]

        TrayTip(title, message, "3")
    }
}

; ============================================================================
; GUI FUNCTIONS
; ============================================================================
CreateMainGUI() {
    global mainGui

    mainGui := Gui("+Resize", "Global Debug Server - Error Console")
    mainGui.BackColor := "2d2d2d"
    mainGui.SetFont("s9 cFFE0E0E0", "Consolas")

    ; Dark mode title bar
    DWMWA_USE_IMMERSIVE_DARK_MODE := 20
    DllCall("dwmapi\DwmSetWindowAttribute",
            "Ptr", mainGui.hwnd,
            "Int", DWMWA_USE_IMMERSIVE_DARK_MODE,
            "Int*", true,
            "Int", 4)

    ; Header
    mainGui.SetFont("s10 cFFFFFF Bold", "Segoe UI")
    mainGui.Add("Text", "w700", "🛡️ Global Debug Server - Active")

    ; Status bar
    mainGui.SetFont("s9 cFFE0E0E0", "Segoe UI")
    statusText := mainGui.Add("Text", "w700",
        "Server: " ServerConfig.bindAddress ":" ServerConfig.port
        . " | Clients: 0 | Errors: 0")
    statusText.Name := "StatusText"

    ; Error list
    mainGui.SetFont("s9 cFFFFFF", "Consolas")
    errorList := mainGui.Add("ListView", "r20 w700 Background1e1e1e cFFFFFF",
                             ["Time", "Script", "Type", "Message", "Line"])
    errorList.Name := "ErrorList"

    ; Apply dark theme to ListView
    DllCall("uxtheme\SetWindowTheme", "Ptr", errorList.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    ; Set column widths
    errorList.ModifyCol(1, 80)   ; Time
    errorList.ModifyCol(2, 150)  ; Script
    errorList.ModifyCol(3, 100)  ; Type
    errorList.ModifyCol(4, 300)  ; Message
    errorList.ModifyCol(5, 50)   ; Line

    ; Buttons
    mainGui.SetFont("s9 cFFFFFF", "Segoe UI")

    btnClear := mainGui.Add("Button", "w100 h30", "Clear")
    btnClear.OnEvent("Click", (*) => ClearErrorList())
    DllCall("uxtheme\SetWindowTheme", "Ptr", btnClear.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    btnExport := mainGui.Add("Button", "w100 h30 x+10", "Export")
    btnExport.OnEvent("Click", (*) => ExportErrors())
    DllCall("uxtheme\SetWindowTheme", "Ptr", btnExport.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    btnStats := mainGui.Add("Button", "w100 h30 x+10", "Statistics")
    btnStats.OnEvent("Click", (*) => ShowStatistics())
    DllCall("uxtheme\SetWindowTheme", "Ptr", btnStats.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    ; Don't show by default
    mainGui.OnEvent("Close", (*) => mainGui.Hide())

    ; Update status periodically
    SetTimer(UpdateStatus, 1000)
}

ShowMainGUI(*) {
    global mainGui
    if (mainGui) {
        mainGui.Show()
    }
}

UpdateErrorList(errorData) {
    global mainGui

    if (!mainGui) {
        return
    }

    errorList := mainGui["ErrorList"]

    time := FormatTime(errorData["timestamp"], "HH:mm:ss")
    script := errorData["script"]
    type := errorData["error"]["type"]
    message := errorData["error"]["message"]
    line := errorData["error"]["line"]

    errorList.Add("", time, script, type, message, line)

    ; Auto-scroll to bottom
    errorList.Modify(errorList.GetCount(), "Vis")
}

ClearErrorList(*) {
    global mainGui
    if (mainGui) {
        mainGui["ErrorList"].Delete()
    }
}

UpdateStatus() {
    global mainGui, clientSockets, errorHistory

    if (!mainGui) {
        return
    }

    statusText := mainGui["StatusText"]
    statusText.Value := "Server: " ServerConfig.bindAddress ":" ServerConfig.port
                      . " | Clients: " clientSockets.Count
                      . " | Errors: " errorHistory.Length
}

ExportErrors(*) {
    global errorHistory

    if (errorHistory.Length == 0) {
        MsgBox("No errors to export", "Export", "i")
        return
    }

    exportFile := A_ScriptDir "\exported_errors_" FormatTime(, "yyyyMMdd_HHmmss") ".txt"

    content := "Global Debug Server - Error Export`n"
    content .= "Generated: " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"
    content .= "Total Errors: " errorHistory.Length "`n"
    content .= "`n════════════════════════════════════════════════════════`n"

    for errorData in errorHistory {
        content .= "`nTimestamp: " errorData["timestamp"] "`n"
        content .= "Script: " errorData["script"] " (PID: " errorData["pid"] ")`n"
        content .= "Error: " errorData["error"]["type"] " - " errorData["error"]["message"] "`n"
        content .= "Location: " errorData["error"]["file"] ":" errorData["error"]["line"] "`n"
        content .= "════════════════════════════════════════════════════════`n"
    }

    FileAppend(content, exportFile, "UTF-8")
    MsgBox("Errors exported to:`n" exportFile, "Export Complete", "i")
}

ShowStatistics(*) {
    global errorHistory, clientSockets

    if (errorHistory.Length == 0) {
        MsgBox("No errors recorded yet", "Statistics", "i")
        return
    }

    ; Count by type
    typeCount := Map()
    scriptCount := Map()

    for errorData in errorHistory {
        type := errorData["error"]["type"]
        script := errorData["script"]

        typeCount[type] := typeCount.Has(type) ? typeCount[type] + 1 : 1
        scriptCount[script] := scriptCount.Has(script) ? scriptCount[script] + 1 : 1
    }

    ; Build statistics message
    stats := "═══ Global Debug Server Statistics ═══`n`n"
    stats .= "Total Errors: " errorHistory.Length "`n"
    stats .= "Active Clients: " clientSockets.Count "`n"
    stats .= "Server Uptime: " Round((A_TickCount - lastNotificationReset) / 60000) " minutes`n`n"

    stats .= "── Errors by Type ──`n"
    for type, count in typeCount {
        stats .= "  " type ": " count "`n"
    }

    stats .= "`n── Errors by Script ──`n"
    for script, count in scriptCount {
        stats .= "  " script ": " count "`n"
    }

    MsgBox(stats, "Statistics", "i")
}

ClearHistory(*) {
    global errorHistory
    errorHistory := []
    ClearErrorList()
    MsgBox("Error history cleared", "Clear", "i")
}

StopServer(*) {
    global isServerRunning, serverSocket, clientSockets

    isServerRunning := false

    ; Close all client connections
    for sock, _ in clientSockets {
        DllCall("ws2_32\closesocket", "Ptr", sock)
    }
    clientSockets := Map()

    ; Close server socket
    if (serverSocket) {
        DllCall("ws2_32\closesocket", "Ptr", serverSocket)
        serverSocket := 0
    }

    ; Cleanup WinSock
    DllCall("ws2_32\WSACleanup")

    A_IconTip := "Global Debug Server - Stopped"
    TrayTip("Server Stopped", "Debug server has been stopped", "2")
}

; ============================================================================
; SIMPLIFIED JSON PARSER (Minimal Implementation)
; ============================================================================
class JSON {
    static Parse(text) {
        ; Simple JSON parser for error packets
        ; Note: This is a minimal implementation - use a full JSON library for production

        result := Map()

        ; Remove outer braces
        text := Trim(RegExReplace(text, "^\{|\}$", ""))

        ; Parse key-value pairs (simplified - doesn't handle nested objects properly)
        pos := 1
        while (pos <= StrLen(text)) {
            ; Find key
            keyStart := InStr(text, '"', , pos)
            if (!keyStart) {
                break
            }
            keyEnd := InStr(text, '"', , keyStart + 1)
            key := SubStr(text, keyStart + 1, keyEnd - keyStart - 1)

            ; Find value
            valueStart := InStr(text, ":", , keyEnd) + 1

            ; Determine value type
            valueStart := RegExReplace(SubStr(text, valueStart), "^\s+")
            valueStart := InStr(text, valueStart, , keyEnd)

            if (SubStr(text, valueStart, 1) == '"') {
                ; String value
                valEnd := InStr(text, '"', , valueStart + 1)
                value := SubStr(text, valueStart + 1, valEnd - valueStart - 1)
                pos := valEnd + 1
            } else if (SubStr(text, valueStart, 1) == "{") {
                ; Object value (simplified - just store as string for now)
                braceCount := 1
                valEnd := valueStart + 1
                while (braceCount > 0 && valEnd <= StrLen(text)) {
                    char := SubStr(text, valEnd, 1)
                    if (char == "{") {
                        braceCount++
                    } else if (char == "}") {
                        braceCount--
                    }
                    valEnd++
                }
                value := SubStr(text, valueStart, valEnd - valueStart)
                pos := valEnd
            } else {
                ; Number or boolean
                valEnd := InStr(text, ",", , valueStart)
                if (!valEnd) {
                    valEnd := StrLen(text) + 1
                }
                value := Trim(SubStr(text, valueStart, valEnd - valueStart))
                pos := valEnd + 1
            }

            result[key] := value

            ; Move to next key
            pos := InStr(text, ",", , pos) + 1
            if (!pos || pos == 1) {
                break
            }
        }

        return result
    }
}

; ============================================================================
; INITIALIZATION
; ============================================================================
DebugServer.Start()
