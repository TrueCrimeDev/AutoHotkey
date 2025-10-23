#Requires AutoHotkey v2.1-alpha.17

; ErrorLogger Class
; Comprehensive error logging and interception system
; Logs all unhandled exceptions to file with full context

class ErrorLogger {
    static Config := Map(
        "logDirectory", A_ScriptDir "\ErrorLogs",
        "logFilePrefix", "ErrorLog_",
        "logFileExtension", ".log",
        "maxLogSize", 5 * 1024 * 1024,
        "logLevels", ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"],
        "logToFile", true,
        "logToConsole", false,
        "logLevel", "INFO",
        "includeStackTrace", true,
        "includeSystemInfo", true,
        "suppressErrorDialog", true,
        "newestLogsAtTop", true,
        "copyToClipboard", true,
        "clipboardFormat", "simple"
    )

    static Instance := ""
    static TestGui := ""

    __New() {
        this.scriptName := A_ScriptName
        this.scriptPath := A_ScriptFullPath
        this.errorCount := 0
        this.logFilePath := this._GetLogFilePath()

        if (!DirExist(ErrorLogger.Config["logDirectory"]))
            DirCreate(ErrorLogger.Config["logDirectory"])

        ErrorLogger.Instance := this

        OnError(this._ErrorHandler.Bind(this))

        this.LogInfo("ErrorLogger initialized for script: " this.scriptName)

        this.ShowTestGui()
    }

    static Debug(message) => ErrorLogger.Instance.LogDebug(message)
    static Info(message) => ErrorLogger.Instance.LogInfo(message)
    static Warning(message) => ErrorLogger.Instance.LogWarning(message)
    static Error(message, exception := "") => ErrorLogger.Instance.LogError(message, exception)
    static Fatal(message, exception := "") => ErrorLogger.Instance.LogFatal(message, exception)

    ShowTestGui() {
        ErrorLogger.TestGui := this.CreateTestGui()
        return ErrorLogger.TestGui
    }

    CreateTestGui() {
        testGui := Gui("+Resize", "Error Logger Test")
        testGui.SetFont("s10")
        testGui.OnEvent("Close", (*) => testGui.Hide())
        testGui.OnEvent("Escape", (*) => testGui.Hide())

        testGui.AddButton("w200", "Simple Error").OnEvent("Click", this.TestSimpleError.Bind(this))
        testGui.AddButton("w200", "Division by Zero").OnEvent("Click", this.TestDivisionByZero.Bind(this))
        testGui.AddButton("w200", "Array Bounds").OnEvent("Click", this.TestArrayBounds.Bind(this))
        testGui.AddButton("w200", "Open Log").OnEvent("Click", this.OpenLogFile.Bind(this))
        testGui.AddButton("w200", "Test Undefined Var").OnEvent("Click", this.TestUndefinedVar.Bind(this))
        testGui.AddButton("w200", "Toggle Log Order").OnEvent("Click", this.ToggleLogOrder.Bind(this))
        testGui.AddButton("w200", "Toggle Clipboard Copy").OnEvent("Click", this.ToggleClipboardCopy.Bind(this))
        testGui.AddButton("w200", "Toggle Clipboard Format").OnEvent("Click", this.ToggleClipboardFormat.Bind(this))

        testGui.Show()
        return testGui
    }

    TestSimpleError(*) {
        this.LogError("This is a test error")
    }

    TestDivisionByZero(*) {
        try {
            result := 10 / 0
        } catch as err {
            this.LogError("Division by zero error", err)
        }
    }

    TestArrayBounds(*) {
        try {
            arr := [1, 2, 3]
            value := arr[10]
        } catch as err {
            this.LogError("Array bounds error", err)
        }
    }

    OpenLogFile(*) {
        if (FileExist(this.logFilePath))
            Run(this.logFilePath)
        else
            MsgBox("Log file does not exist: " this.logFilePath)
    }

    TestUndefinedVar(*) {
        try {
            definedVar := 10
            someVar := definedVar + 5
            MsgBox("Test successful: " someVar)
        } catch as err {
            this.LogError("Variable error", err)
        }
    }

    ToggleLogOrder(*) {
        ErrorLogger.Config["newestLogsAtTop"] := !ErrorLogger.Config["newestLogsAtTop"]
        MsgBox("Log order changed: " (ErrorLogger.Config["newestLogsAtTop"] ? "Newest at top" : "Newest at bottom"))
    }

    ToggleClipboardCopy(*) {
        isEnabled := this.ToggleClipboardCopyOption()
        MsgBox("Clipboard copy is now " . (isEnabled ? "enabled" : "disabled"))
    }

    ToggleClipboardFormat(*) {
        currentFormat := ErrorLogger.Config["clipboardFormat"]
        newFormat := (currentFormat = "simple") ? "detailed" : "simple"
        this.SetClipboardFormatOption(newFormat)
        MsgBox("Clipboard format changed to: " . newFormat)
    }

    _GetLogFilePath() {
        dateStr := FormatTime(A_Now, "yyyy_MM_dd")
        return ErrorLogger.Config["logDirectory"] "\"
             . ErrorLogger.Config["logFilePrefix"]
             . dateStr
             . ErrorLogger.Config["logFileExtension"]
    }

    _FormatLogEntry(level, message) {
        timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        return "[" timestamp "] [" level "] " message
    }

    _WriteLog(entry) {
        try {
            if (FileExist(this.logFilePath)) {
                fileObj := FileOpen(this.logFilePath, "r")
                if (fileObj) {
                    size := fileObj.Length

                    if (size > ErrorLogger.Config["maxLogSize"]) {
                        fileObj.Close()

                        archiveTime := FormatTime(A_Now, "yyyyMMdd_HHmmss")
                        archivePath := ErrorLogger.Config["logDirectory"] "\"
                                      . ErrorLogger.Config["logFilePrefix"]
                                      . archiveTime "_archive"
                                      . ErrorLogger.Config["logFileExtension"]

                        try {
                            FileCopy(this.logFilePath, archivePath)
                            FileDelete(this.logFilePath)
                        } catch as err {
                            this._ShowTooltip("Warning", "Failed to archive log: " err.Message)
                        }

                        FileAppend(entry "`n", this.logFilePath)
                    } else {
                        existingContent := fileObj.Read()
                        fileObj.Close()

                        if (ErrorLogger.Config["newestLogsAtTop"]) {
                            FileOpen(this.logFilePath, "w").Close()
                            FileAppend(entry "`n" existingContent, this.logFilePath)
                        } else {
                            FileAppend(entry "`n", this.logFilePath)
                        }
                    }
                }
            } else {
                FileAppend(entry "`n", this.logFilePath)
            }
        } catch as err {
            if (ErrorLogger.Config["logToConsole"])
                OutputDebug("Error writing to log: " err.Message "`nOriginal entry: " entry)
            this._ShowTooltip("Error", "Failed to write to log: " err.Message)
        }
    }

    _ShowTooltip(level, message, duration := 3000) {
        ToolTip(level ": " message)
        SetTimer(() => ToolTip(), -duration)
    }

    _IsLevelEnabled(level) {
        levels := ErrorLogger.Config["logLevels"]
        configLevel := ErrorLogger.Config["logLevel"]

        levelIndex := -1
        configLevelIndex := -1

        for i, lvl in levels {
            if (lvl = level)
                levelIndex := i
            if (lvl = configLevel)
                configLevelIndex := i
        }

        return levelIndex >= configLevelIndex
    }

    _FormatTimestamp(timestamp) {
        return FormatTime(timestamp, "yyyy-MM-dd HH:mm:ss")
    }

    _GetCodeContext(file, line) {
        try {
            if (FileExist(file)) {
                fileContent := FileRead(file)
                lines := StrSplit(fileContent, "`n", "`r")

                if (line <= lines.Length)
                    return Trim(lines[line])
            }
        } catch as err {
            this._ShowTooltip("Error", "Error reading file: " file ", Line: " line)
        }

        return ""
    }

    _FormatStackContext(exception) {
        try {
            if (exception.HasProp("File") && exception.HasProp("Line")) {
                exceptionFile := exception.File
                exceptionLine := exception.Line

                if (FileExist(exceptionFile)) {
                    fileContent := FileRead(exceptionFile)
                    lines := StrSplit(fileContent, "`n", "`r")

                    contextLines := ""
                    contextStart := Max(1, exceptionLine - 2)
                    contextEnd := Min(lines.Length, exceptionLine + 2)

                    Loop (contextEnd - contextStart + 1) {
                        currentLine := contextStart + A_Index - 1
                        lineMarker := (currentLine = exceptionLine) ? "→ " : "  "
                        contextLines .= lineMarker Format("{1:4}", currentLine) ": " lines[currentLine] "`n"
                    }

                    return contextLines
                }
            }
        } catch as err {
            this._ShowTooltip("Error", "Error formatting stack context: " err.Message)
        }

        return ""
    }

    _ErrorHandler(exception, mode) {
        this.LogError("Unhandled exception", exception)
        return ErrorLogger.Config["suppressErrorDialog"] ? 1 : 0
    }

    CopyErrorToClipboard(message, exception := "") {
        clipText := ""

        if (ErrorLogger.Config["clipboardFormat"] = "simple") {
            clipText := "Error: " . (Type(exception) != "String" ? exception.Message : message) . "`n"
            if (Type(exception) != "String" && exception.HasProp("File") && exception.HasProp("Line"))
                clipText .= "Location: " . exception.File . ":" . exception.Line . "`n"
        } else {
            clipText := "===== ERROR DETAILS =====`n"
            clipText .= "Time: " . this._FormatTimestamp(A_Now) . "`n"
            clipText .= "Message: " . (Type(exception) != "String" ? exception.Message : message) . "`n"

            if (Type(exception) != "String") {
                if (exception.HasProp("File"))
                    clipText .= "File: " . exception.File . "`n"

                if (exception.HasProp("Line"))
                    clipText .= "Line: " . exception.Line . "`n"

                if (exception.HasProp("What"))
                    clipText .= "Function: " . exception.What . "`n"

                if (exception.HasProp("Extra"))
                    clipText .= "Extra Info: " . exception.Extra . "`n"

                if (exception.HasProp("Stack"))
                    clipText .= "`nStack Trace:`n" . exception.Stack . "`n"
            }

            clipText .= "Script: " . A_ScriptName . "`n"
            clipText .= "AHK Version: " . A_AhkVersion . "`n"
        }

        try {
            A_Clipboard := clipText
            this._ShowTooltip("Info", "Error details copied to clipboard")
        } catch as err {
            this._ShowTooltip("Warning", "Failed to copy to clipboard: " . err.Message)
        }

        return clipText
    }

    ToggleClipboardCopyOption(enable := -1) {
        if (enable = -1)
            ErrorLogger.Config["copyToClipboard"] := !ErrorLogger.Config["copyToClipboard"]
        else
            ErrorLogger.Config["copyToClipboard"] := enable

        return ErrorLogger.Config["copyToClipboard"]
    }

    SetClipboardFormatOption(format := "simple") {
        if (format = "simple" || format = "detailed")
            ErrorLogger.Config["clipboardFormat"] := format

        return ErrorLogger.Config["clipboardFormat"]
    }

    LogDebug(message) {
        if (this._IsLevelEnabled("DEBUG")) {
            entry := this._FormatLogEntry("DEBUG", message)
            this._WriteLog(entry)

            if (ErrorLogger.Config["logToConsole"])
                OutputDebug(entry)
        }
    }

    LogInfo(message) {
        if (this._IsLevelEnabled("INFO")) {
            entry := this._FormatLogEntry("INFO", message)
            this._WriteLog(entry)

            if (ErrorLogger.Config["logToConsole"])
                OutputDebug(entry)
        }
    }

    LogWarning(message) {
        if (this._IsLevelEnabled("WARN")) {
            entry := this._FormatLogEntry("WARN", message)
            this._WriteLog(entry)

            if (ErrorLogger.Config["logToConsole"])
                OutputDebug(entry)
        }
    }

    LogError(message, exception := "") {
        if (this._IsLevelEnabled("ERROR")) {
            this.errorCount++

            entry := this._FormatLogEntry("ERROR", "===== ERROR [" this._FormatTimestamp(A_Now) "] =====")
            this._WriteLog(entry)

            if (exception != "") {
                this._WriteLog("Type: " (Type(exception) != "String" ? Type(exception) : "Custom"))
                this._WriteLog("Message: " (Type(exception) != "String" ? exception.Message : exception))

                if (Type(exception) != "String" && exception.HasProp("File"))
                    this._WriteLog("File: " exception.File)

                if (Type(exception) != "String" && exception.HasProp("Line"))
                    this._WriteLog("Line: " exception.Line)

                if (Type(exception) != "String" && exception.HasProp("Extra"))
                    this._WriteLog("Extra: " exception.Extra)

                if (Type(exception) != "String" && exception.HasProp("What"))
                    this._WriteLog("What: " exception.What)

                if (Type(exception) != "String" && exception.HasProp("File") && exception.HasProp("Line")) {
                    try {
                        code := this._GetCodeContext(exception.File, exception.Line)
                        if (code)
                            this._WriteLog("Code: " code)
                    } catch as err {
                        this._WriteLog("Error getting code context: " err.Message)
                    }
                }

                if (ErrorLogger.Config["includeStackTrace"] && Type(exception) != "String" && exception.HasProp("Stack")) {
                    this._WriteLog("`nContext:")
                    this._WriteLog(this._FormatStackContext(exception))

                    this._WriteLog("`nStack Trace:")
                    this._WriteLog(exception.Stack)
                }

                this._WriteLog("`n`nThis is error #" this.errorCount " since script start.")

                if (ErrorLogger.Config["includeSystemInfo"]) {
                    this._WriteLog("`n===== System Information =====")
                    this._WriteLog("AHK Version: " A_AhkVersion)
                    this._WriteLog("Script: " A_ScriptName)
                    this._WriteLog("Script Path: " A_ScriptFullPath)
                    this._WriteLog("Working Dir: " A_WorkingDir)
                }
            } else {
                this._WriteLog(message)
            }

            if (ErrorLogger.Config["logToConsole"])
                OutputDebug(entry)

            if (ErrorLogger.Config["copyToClipboard"])
                this.CopyErrorToClipboard(message, exception)
        }
    }

    LogFatal(message, exception := "") {
        if (this._IsLevelEnabled("FATAL")) {
            entry := this._FormatLogEntry("FATAL", message)
            this._WriteLog(entry)

            this.LogError(message, exception)

            if (ErrorLogger.Config["logToConsole"])
                OutputDebug(entry)
        }
    }
}
