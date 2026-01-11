#Requires AutoHotkey v2.1-alpha.17

; DebuggerInterceptor Configuration Examples
; Modify these examples to customize the system for your needs

#Include Initialize.ahk

; ============================================================================
; EXAMPLE 1: Development Mode (Verbose Logging)
; ============================================================================
; Setup for development with maximum logging detail

ConfigureDevelopmentMode() {
    ErrorLogger.Config["logLevel"] := "DEBUG"                ; Log everything
    ErrorLogger.Config["includeStackTrace"] := true          ; Include full traces
    ErrorLogger.Config["includeSystemInfo"] := true          ; System info
    ErrorLogger.Config["suppressErrorDialog"] := false       ; Show error dialogs
    ErrorLogger.Config["copyToClipboard"] := true            ; Auto-copy to clipboard
    ErrorLogger.Config["clipboardFormat"] := "detailed"      ; Detailed format
    ErrorLogger.Config["newestLogsAtTop"] := true            ; Newest first
    ErrorLogger.Config["logToConsole"] := true               ; Also output to console

    InitializeDebuggerInterceptor(true)  ; Show test GUI
}


; ============================================================================
; EXAMPLE 2: Production Mode (Error Only)
; ============================================================================
; Setup for production with minimal overhead

ConfigureProductionMode() {
    ErrorLogger.Config["logLevel"] := "ERROR"                ; Only errors and fatal
    ErrorLogger.Config["includeStackTrace"] := true          ; Still include traces
    ErrorLogger.Config["includeSystemInfo"] := true          ; Keep system info
    ErrorLogger.Config["suppressErrorDialog"] := true        ; Hide error dialogs
    ErrorLogger.Config["copyToClipboard"] := false           ; No clipboard copy
    ErrorLogger.Config["logToConsole"] := false              ; No console output

    InitializeDebuggerInterceptor(false)  ; Don't show test GUI
}


; ============================================================================
; EXAMPLE 3: Testing Mode (Balanced)
; ============================================================================
; Setup for testing with detailed errors but no warnings

ConfigureTestingMode() {
    ErrorLogger.Config["logLevel"] := "WARN"                 ; Warnings and errors
    ErrorLogger.Config["includeStackTrace"] := true
    ErrorLogger.Config["includeSystemInfo"] := false         ; Skip system info
    ErrorLogger.Config["suppressErrorDialog"] := true
    ErrorLogger.Config["copyToClipboard"] := true
    ErrorLogger.Config["clipboardFormat"] := "simple"        ; Simple format
    ErrorLogger.Config["maxLogSize"] := 2 * 1024 * 1024      ; Smaller max size

    InitializeDebuggerInterceptor(true)
}


; ============================================================================
; EXAMPLE 4: Minimal Logging
; ============================================================================
; Setup with minimal logging for performance-critical scripts

ConfigureMinimalMode() {
    ErrorLogger.Config["logLevel"] := "ERROR"
    ErrorLogger.Config["includeStackTrace"] := false         ; No stack traces
    ErrorLogger.Config["includeSystemInfo"] := false         ; No system info
    ErrorLogger.Config["suppressErrorDialog"] := true
    ErrorLogger.Config["copyToClipboard"] := false
    ErrorLogger.Config["logToFile"] := true                  ; Still log to file

    InitializeDebuggerInterceptor(false)
}


; ============================================================================
; EXAMPLE 5: Custom Directory Configuration
; ============================================================================
; Setup with custom log locations

ConfigureCustomDirectories() {
    ErrorLogger.Config["logDirectory"] := "C:\MyApp\Logs\Errors"
    ErrorLogger.Config["logFilePrefix"] := "MyApp_Error_"
    ErrorLogger.Config["logFileExtension"] := ".txt"

    LogViewer.Config["errorLogsDir"] := "C:\MyApp\Logs\Errors"

    InitializeDebuggerInterceptor(false)
}


; ============================================================================
; EXAMPLE 6: Clipboard Configuration
; ============================================================================
; Various clipboard copy behaviors

ConfigureClipboardOptions() {
    ; Option A: Copy detailed errors to clipboard
    ErrorLogger.Config["copyToClipboard"] := true
    ErrorLogger.Config["clipboardFormat"] := "detailed"

    ; Option B: Copy simple error messages
    ; ErrorLogger.Config["copyToClipboard"] := true
    ; ErrorLogger.Config["clipboardFormat"] := "simple"

    ; Option C: Don't copy to clipboard
    ; ErrorLogger.Config["copyToClipboard"] := false

    InitializeDebuggerInterceptor(false)
}


; ============================================================================
; EXAMPLE 7: LogViewer UI Configuration
; ============================================================================
; Customize the viewer interface

ConfigureLogViewerUI() {
    LogViewer.Config["defaultWidth"] := 1200
    LogViewer.Config["defaultHeight"] := 800
    LogViewer.Config["refreshInterval"] := 1000    ; Faster refresh
    LogViewer.Config["maxEntries"] := 10000        ; Show more entries

    InitializeDebuggerInterceptor(false)
}


; ============================================================================
; EXAMPLE 8: Full Custom Configuration
; ============================================================================
; Everything customized for specific use case

ConfigureFullCustom() {
    ; Logging
    ErrorLogger.Config["logDirectory"] := A_ScriptDir "\AppLogs"
    ErrorLogger.Config["logLevel"] := "INFO"
    ErrorLogger.Config["maxLogSize"] := 10 * 1024 * 1024

    ; Details
    ErrorLogger.Config["includeStackTrace"] := true
    ErrorLogger.Config["includeSystemInfo"] := true
    ErrorLogger.Config["suppressErrorDialog"] := true

    ; Clipboard
    ErrorLogger.Config["copyToClipboard"] := true
    ErrorLogger.Config["clipboardFormat"] := "detailed"
    ErrorLogger.Config["newestLogsAtTop"] := true

    ; UI
    LogViewer.Config["refreshInterval"] := 1500
    LogViewer.Config["defaultWidth"] := 1000
    LogViewer.Config["defaultHeight"] := 700

    InitializeDebuggerInterceptor(false)
}


; ============================================================================
; USAGE: Choose one of the above configurations
; ============================================================================
; Uncomment the configuration you want to use:

; ConfigureDevelopmentMode()
; ConfigureProductionMode()
; ConfigureTestingMode()
; ConfigureMinimalMode()
; ConfigureCustomDirectories()
; ConfigureClipboardOptions()
; ConfigureLogViewerUI()
; ConfigureFullCustom()

; Or just call directly without configuration:
; InitializeDebuggerInterceptor()
