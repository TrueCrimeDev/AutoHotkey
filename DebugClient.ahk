#Requires AutoHotkey v2.0
; ============================================================================
; DebugClient.ahk
; Lightweight TCP client for global error reporting
; ============================================================================
; Description: Include this file in any script to enable automatic error
;              reporting to GlobalDebugServer. Minimal overhead (~100 lines).
; Usage: Add one line to your script:
;        #Include DebugClient.ahk
; ============================================================================

; ============================================================================
; CLIENT CONFIGURATION
; ============================================================================
class ClientConfig {
    static serverHost := "127.0.0.1"  ; Server IP (use actual IP for remote)
    static serverPort := 9999         ; Must match GlobalDebugServer port
    static reconnectInterval := 5000  ; ms between reconnect attempts
    static sendTimeout := 100         ; ms timeout for send operations
    static fallbackToFile := true     ; Write to file if server unavailable
    static fallbackLogDir := A_ScriptDir "\ErrorLogs"
}

; ============================================================================
; DEBUG CLIENT CLASS
; ============================================================================
class DebugClient {
    static socket := 0
    static connected := false
    static reconnectTimer := 0

    /**
     * Initialize client and register error handler
     */
    static Initialize() {
        ; Connect to server
        this.Connect()

        ; Register global error handler
        OnError(this.CaptureError.Bind(this), 1)

        ; If connection failed, set up reconnect timer
        if (!this.connected && ClientConfig.reconnectInterval > 0) {
            this.reconnectTimer := ClientConfig.reconnectInterval
            SetTimer(() => this.Reconnect(), ClientConfig.reconnectInterval)
        }
    }

    /**
     * Connect to GlobalDebugServer via TCP
     */
    static Connect() {
        try {
            ; Initialize WinSock
            static WSADATA_SIZE := 400
            wsaData := Buffer(WSADATA_SIZE, 0)

            if (DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData)) {
                return false
            }

            ; Create socket
            static AF_INET := 2
            static SOCK_STREAM := 1
            static IPPROTO_TCP := 6

            this.socket := DllCall("ws2_32\socket",
                                   "Int", AF_INET,
                                   "Int", SOCK_STREAM,
                                   "Int", IPPROTO_TCP,
                                   "Ptr")

            if (this.socket == -1) {
                return false
            }

            ; Set socket to non-blocking mode
            static FIONBIO := 0x8004667E
            mode := 1
            DllCall("ws2_32\ioctlsocket", "Ptr", this.socket, "UInt", FIONBIO, "UInt*", &mode)

            ; Build server address structure
            sockaddr := Buffer(16, 0)
            NumPut("UShort", AF_INET, sockaddr, 0)
            NumPut("UShort", DllCall("ws2_32\htons", "UShort", ClientConfig.serverPort, "UShort"), sockaddr, 2)

            ; Convert IP address
            ipAddr := DllCall("ws2_32\inet_addr", "AStr", ClientConfig.serverHost, "UInt")
            NumPut("UInt", ipAddr, sockaddr, 4)

            ; Attempt connection (non-blocking)
            DllCall("ws2_32\connect", "Ptr", this.socket, "Ptr", sockaddr, "Int", 16)

            ; For non-blocking socket, connection may not be immediate
            ; We'll consider it connected and handle send errors later
            this.connected := true

            ; Give connection a moment to establish
            Sleep(50)

            return true

        } catch {
            this.connected := false
            this.socket := 0
            return false
        }
    }

    /**
     * Attempt to reconnect to server
     */
    static Reconnect() {
        if (!this.connected) {
            this.Connect()
        }
    }

    /**
     * Main error capture handler (called by OnError hook)
     */
    static CaptureError(exception, mode) {
        ; Build error packet
        packet := this.BuildErrorPacket(exception)

        ; Try to send to server
        if (this.connected) {
            success := this.SendToServer(packet)

            ; If send failed, mark as disconnected
            if (!success) {
                this.connected := false
            }
        }

        ; Fallback to file if server unavailable
        if (!this.connected && ClientConfig.fallbackToFile) {
            this.LogToFile(packet)
        }

        ; Suppress default error dialog
        return -1
    }

    /**
     * Build JSON error packet
     */
    static BuildErrorPacket(exception) {
        ; Extract error details
        errorData := Map(
            "type", "error",
            "script", A_ScriptName,
            "pid", DllCall("GetCurrentProcessId"),
            "timestamp", FormatTime(A_Now, "yyyy-MM-ddTHH:mm:ss"),
            "error", Map(
                "type", Type(exception),
                "message", this.EscapeJSON(exception.Message),
                "file", this.EscapeJSON(exception.File),
                "line", exception.Line,
                "what", exception.What ? this.EscapeJSON(exception.What) : "",
                "stack", exception.HasProp("Stack") ? this.EscapeJSON(exception.Stack) : "",
                "extra", exception.HasProp("Extra") ? this.EscapeJSON(exception.Extra) : ""
            )
        )

        ; Convert to JSON string (manually for minimal dependencies)
        json := "{"
        json .= '"type":"' errorData["type"] '",'
        json .= '"script":"' this.EscapeJSON(errorData["script"]) '",'
        json .= '"pid":' errorData["pid"] ','
        json .= '"timestamp":"' errorData["timestamp"] '",'
        json .= '"error":{'
        json .= '"type":"' errorData["error"]["type"] '",'
        json .= '"message":"' errorData["error"]["message"] '",'
        json .= '"file":"' errorData["error"]["file"] '",'
        json .= '"line":' errorData["error"]["line"] ','
        json .= '"what":"' errorData["error"]["what"] '",'
        json .= '"stack":"' errorData["error"]["stack"] '",'
        json .= '"extra":"' errorData["error"]["extra"] '"'
        json .= "}}"

        return json
    }

    /**
     * Escape string for JSON
     */
    static EscapeJSON(str) {
        str := StrReplace(str, "\", "\\")
        str := StrReplace(str, '"', '\"')
        str := StrReplace(str, "`n", "\n")
        str := StrReplace(str, "`r", "\r")
        str := StrReplace(str, "`t", "\t")
        return str
    }

    /**
     * Send packet to server
     */
    static SendToServer(packet) {
        if (!this.socket || !this.connected) {
            return false
        }

        try {
            ; Add newline delimiter
            packet .= "`n"

            ; Convert to UTF-8 bytes
            bytesNeeded := StrPut(packet, "UTF-8") - 1
            buffer := Buffer(bytesNeeded, 0)
            StrPut(packet, buffer, "UTF-8")

            ; Send data
            bytesSent := DllCall("ws2_32\send",
                                 "Ptr", this.socket,
                                 "Ptr", buffer,
                                 "Int", bytesNeeded,
                                 "Int", 0,
                                 "Int")

            return (bytesSent > 0)

        } catch {
            return false
        }
    }

    /**
     * Fallback: Log error to local file
     */
    static LogToFile(packet) {
        try {
            ; Create log directory
            if (!DirExist(ClientConfig.fallbackLogDir)) {
                DirCreate(ClientConfig.fallbackLogDir)
            }

            ; Write to daily log file
            logFile := ClientConfig.fallbackLogDir
                     . "\client_error_log_"
                     . FormatTime(, "yyyy-MM-dd")
                     . ".txt"

            ; Parse packet for readable format
            entry := "`n════════════════════════════════════════════════════════`n"
            entry .= "CLIENT ERROR (Server Unavailable)`n"
            entry .= FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"
            entry .= "Script: " A_ScriptName " (PID: " DllCall("GetCurrentProcessId") ")`n"
            entry .= "`nRAW PACKET:`n" packet "`n"
            entry .= "════════════════════════════════════════════════════════`n"

            FileAppend(entry, logFile, "UTF-8")

        } catch {
            ; Silently fail - can't do anything if file logging also fails
        }
    }

    /**
     * Cleanup on script exit
     */
    static Cleanup() {
        if (this.socket) {
            DllCall("ws2_32\closesocket", "Ptr", this.socket)
            DllCall("ws2_32\WSACleanup")
        }
    }
}

; ============================================================================
; AUTO-INITIALIZE
; ============================================================================
; Automatically initialize client when this file is included
DebugClient.Initialize()

; Register cleanup on exit
OnExit((*) => DebugClient.Cleanup())
