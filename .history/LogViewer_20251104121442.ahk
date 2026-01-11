#Requires AutoHotkey v2.1-alpha.17
#SingleInstance Force

; LogViewer Class
; GUI interface for browsing and analyzing error logs
; Real-time monitoring with filtering and search capabilities

viewer := LogViewer()
viewer.Show()

class LogViewer {
    static Config := Map(
        "defaultLogFile", A_ScriptDir "\ahk_error_log.txt",
        "refreshInterval", 2000,
        "maxEntries", 5000,
        "defaultWidth", 900,
        "defaultHeight", 600,
        "levels", ["ALL", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"],
        "errorLogsDir", A_ScriptDir "\ErrorLogs"
    )

    __New() {
        this.logEntries := []
        this.filterLevel := "ALL"
        this.searchText := ""
        this.autoRefresh := true
        this.logFile := LogViewer.Config["defaultLogFile"]

        this.gui := Gui("+Resize +MinSize500x300", "Log Viewer")
        this.gui.BackColor := "0x202020"
        this.gui.SetFont("s10 cWhite", "Segoe UI")

        this.gui.OnEvent("Size", this.OnSize.Bind(this))
        this.gui.OnEvent("Close", (*) => this.gui.Hide())
        this.gui.OnEvent("Escape", (*) => this.gui.Hide())

        this.SetupControls()

        this.ReadLogFile()

        this.refreshTimer := this.RefreshLogView.Bind(this)
        SetTimer(this.refreshTimer, LogViewer.Config["refreshInterval"])
    }

    SetupControls() {
        ; Top toolbar
        this.gui.AddText("x10 y10 w80", "Log File:")
        this.fileEdit := this.gui.AddEdit("x90 y8 w400 ReadOnly", this.logFile)
        this.browseBtn := this.gui.AddButton("x500 y7 w80", "Browse")
        this.browseBtn.OnEvent("Click", this.BrowseLogFile.Bind(this))

        ; Add Error Logs button
        this.errorLogsBtn := this.gui.AddButton("x590 y7 w120", "Error Logs")
        this.errorLogsBtn.OnEvent("Click", this.OpenErrorLogs.Bind(this))

        ; Filter controls
        this.gui.AddText("x10 y42 w80", "Filter Level:")
        this.levelCombo := this.gui.AddComboBox("x90 y40 w120 Choose1", LogViewer.Config["levels"])
        this.levelCombo.OnEvent("Change", this.OnLevelChange.Bind(this))

        this.gui.AddText("x230 y42 w80", "Search:")
        this.searchEdit := this.gui.AddEdit("x310 y40 w200")
        this.searchBtn := this.gui.AddButton("x520 y40 w80", "Search")
        this.searchBtn.OnEvent("Click", this.OnSearch.Bind(this))

        this.refreshChk := this.gui.AddCheckBox("x620 y40 w120 Checked", "Auto Refresh")
        this.refreshChk.OnEvent("Click", this.OnRefreshToggle.Bind(this))

        this.refreshBtn := this.gui.AddButton("x750 y40 w60", "Refresh")
        this.refreshBtn.OnEvent("Click", this.OnRefreshClick.Bind(this))

        this.clearBtn := this.gui.AddButton("x820 y40 w70", "Clear Log")
        this.clearBtn.OnEvent("Click", this.OnClearLog.Bind(this))

        ; Main log view
        this.lvOpts := "x10 y80 w880 h500 Grid"
        this.lv := this.gui.AddListView(this.lvOpts, ["Time", "Level", "Message", "Source", "Line"])

        ; Configure columns
        this.lv.ModifyCol(1, 180)
        this.lv.ModifyCol(2, 80)
        this.lv.ModifyCol(3, 400)
        this.lv.ModifyCol(4, 150)
        this.lv.ModifyCol(5, 50)

        ; Apply dark mode to ListView directly
        this.ApplyDarkModeToListView(this.lv)

        ; Add ListView event handlers
        this.lv.OnEvent("DoubleClick", this.ShowErrorDetails.Bind(this))
        this.lv.OnEvent("ContextMenu", this.ShowContextMenu.Bind(this))

        ; Status bar
        this.statusBar := this.gui.AddText("x10 y585 w880 h20 vStatusBar", "Ready")
    }

    ApplyDarkModeToListView(lv) {
        static LVM_GETHEADER := 0x101F
        static LVS_EX_DOUBLEBUFFER := 0x10000
        static LVM_SETTEXTBKCOLOR := 0x1029
        static LVM_SETTEXTCOLOR := 0x1026
        static LVM_SETBKCOLOR := 0x1001

        ; Set the ListView text color to white
        SendMessage(LVM_SETTEXTCOLOR, 0, 0xFFFFFF, lv)

        ; Set the ListView background to dark
        SendMessage(LVM_SETBKCOLOR, 0, 0x202020, lv)

        ; Set text background to transparent (same as background)
        SendMessage(LVM_SETTEXTBKCOLOR, 0, 0x202020, lv)

        ; Get and style the header
        header := SendMessage(LVM_GETHEADER, 0, 0, lv)
        if (header) {
            lv.DefineProp("Header", { Value: header })

            ; Set header text color
            SendMessage(0x1053, 0, 0xFFFFFF, header)  ; HDM_SETTEXTCOLOR
            ; Set header background color
            SendMessage(0x1054, 0, 0x2D2D2D, header)  ; HDM_SETBKCOLOR
        }

        ; Apply double buffering
        lv.Opt("+LV" LVS_EX_DOUBLEBUFFER)

        ; Try to apply dark mode theme if available
        try {
            DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
            if (header)
                DllCall("uxtheme\SetWindowTheme", "Ptr", header, "Str", "DarkMode_ItemsView", "Ptr", 0)
        }
    }

    ReadLogFile() {
        this.logEntries := []

        if (!FileExist(this.logFile)) {
            this.UpdateStatus("Log file not found: " this.logFile)
            return
        }

        try {
            fileContent := FileRead(this.logFile)
            this.logEntries := this.ParseLogFile(fileContent)
            this.UpdateStatus("Loaded " this.logEntries.Length " log entries")
        }
        catch as err {
            this.UpdateStatus("Error reading log file: " err.Message)
        }
    }

    ParseLogFile(fileContent) {
        entries := []
        lines := StrSplit(fileContent, "`n", "`r")

        i := 1
        while (i <= lines.Length) {
            line := lines[i]

            if (Trim(line) = "") {
                i++
                continue
            }

            if (RegExMatch(line, "^\[\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\]")) {
                entry := Map(
                    "Time", "",
                    "Level", "INFO",
                    "Message", "",
                    "Type", "",
                    "Source", "",
                    "Line", "",
                    "FullText", line
                )

                if (timeMatch := RegExMatch(line, "^\[(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\]", &matches))
                    entry["Time"] := matches[1]

                if (levelMatch := RegExMatch(line, "\[(DEBUG|INFO|WARN|ERROR|FATAL)\]", &matches))
                    entry["Level"] := matches[1]

                if (InStr(line, "[ERROR]")) {
                    errorText := line . "`n"
                    errorStarted := true

                    i++
                    while (i <= lines.Length) {
                        currentLine := lines[i]

                        if (RegExMatch(currentLine, "^\[\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\]") &&
                            !RegExMatch(currentLine, "===== ERROR \[\d{4}-\d{2}-\d{2}"))
                            break

                        if (RegExMatch(currentLine, "Type:\s+(.+)$", &typeMatch))
                            entry["Type"] := typeMatch[1]
                        else if (RegExMatch(currentLine, "Message:\s+(.+)$", &msgMatch))
                            entry["Message"] := msgMatch[1]
                        else if (RegExMatch(currentLine, "File:\s+(.+)$", &fileMatch))
                            entry["Source"] := fileMatch[1]
                        else if (RegExMatch(currentLine, "Line:\s+(\d+)", &lineMatch))
                            entry["Line"] := lineMatch[1]

                        errorText .= currentLine . "`n"
                        i++
                    }

                    if (entry["Message"] = "")
                        entry["Message"] := "Error: See details"

                    entry["FullText"] := errorText
                } else {
                    entry["Message"] := RegExReplace(line, "^\[\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\]\s*\[(DEBUG|INFO|WARN|ERROR|FATAL)\]\s*", "")
                    i++
                }

                entries.Push(entry)
            } else {
                i++
            }
        }

        return entries
    }

    RefreshLogView() {
        if (!WinExist("ahk_id " this.gui.Hwnd))
            return

        if (this.autoRefresh)
            this.ReadLogFile()

        this.lv.Delete()

        filteredEntries := []

        for entry in this.logEntries {
            if (this.filterLevel != "ALL" && entry["Level"] != this.filterLevel)
                continue

            if (this.searchText && !InStr(entry["Message"], this.searchText) &&
                !InStr(entry["Source"], this.searchText) &&
                !InStr(entry["FullText"], this.searchText))
                continue

            filteredEntries.Push(entry)
        }

        if (filteredEntries.Length > 0) {
            Loop filteredEntries.Length {
                index := filteredEntries.Length - (A_Index - 1)
                entry := filteredEntries[index]

                rowIndex := this.lv.Add(,
                    entry["Time"],
                    entry["Level"],
                    Trim(entry["Message"]),
                    entry["Source"],
                    entry["Line"]
                )

                this.lv.DefineProp("Row" rowIndex "Data", { Value: entry })

                if (entry["Level"] = "ERROR" || entry["Level"] = "FATAL")
                    this.lv.Row(rowIndex).SetColor("0xFF5050")
                else if (entry["Level"] = "WARN")
                    this.lv.Row(rowIndex).SetColor("0xFFA500")
                else if (entry["Level"] = "DEBUG")
                    this.lv.Row(rowIndex).SetColor("0x8080FF")
            }
        }

        this.UpdateStatus("Displaying " filteredEntries.Length " of " this.logEntries.Length " log entries")
    }

    BrowseLogFile(*) {
        selectedFile := FileSelect(3, A_ScriptDir, "Select Log File", "Log Files (*.txt; *.log)")
        if (selectedFile) {
            this.logFile := selectedFile
            this.fileEdit.Value := selectedFile
            this.ReadLogFile()
            this.RefreshLogView()
        }
    }

    OpenErrorLogs(*) {
        errorLogsDir := LogViewer.Config["errorLogsDir"]
        if (!DirExist(errorLogsDir)) {
            try {
                DirCreate(errorLogsDir)
                this.UpdateStatus("Created error logs directory: " errorLogsDir)
            } catch {
                this.UpdateStatus("Error logs directory not found: " errorLogsDir)
                return
            }
        }

        errorLogs := []
        Loop Files, errorLogsDir "\*.txt"
            errorLogs.Push(A_LoopFileFullPath)

        if (errorLogs.Length = 0) {
            this.UpdateStatus("No error log files found in " errorLogsDir)
            return
        }

        menu := Menu()
        for file in errorLogs {
            filename := RegExReplace(file, ".*\\")
            menu.Add(filename, this.LoadErrorLog.Bind(this, file))
        }

        menu.Add()
        menu.Add("Browse for Error Log...", this.BrowseLogFile.Bind(this))

        menu.Show()
    }

    LoadErrorLog(file, *) {
        this.logFile := file
        this.fileEdit.Value := file
        this.ReadLogFile()
        this.RefreshLogView()
    }

    ShowErrorDetails(*) {
        selectedRow := this.lv.GetNext(0)
        if (!selectedRow)
            return

        entry := this.lv.%"Row" selectedRow "Data"%
        if (!entry || !entry.Has("FullText"))
            return

        detailsGui := Gui("+Resize +MinSize400x300", "Error Details")
        detailsGui.SetFont("s10", "Consolas")
        detailsEdit := detailsGui.AddEdit("w600 h400 ReadOnly", entry["FullText"])

        copyBtn := detailsGui.AddButton("w100 Default", "Copy to Clipboard")
        copyBtn.OnEvent("Click", (*) => (A_Clipboard := entry["FullText"], detailsGui.Destroy()))

        closeBtn := detailsGui.AddButton("w100 x+10", "Close")
        closeBtn.OnEvent("Click", (*) => detailsGui.Destroy())

        detailsGui.Show("w600 h440")
    }

    ShowContextMenu(*) {
        selectedRow := this.lv.GetNext(0)
        if (!selectedRow)
            return

        menu := Menu()
        menu.Add("Show Details", this.ShowErrorDetails.Bind(this))
        menu.Add("Copy to Clipboard", this.CopyErrorToClipboard.Bind(this))
        menu.Add("Filter by Level", this.FilterByLevel.Bind(this, selectedRow))
        menu.Add("Search for Similar Errors", this.SearchSimilarErrors.Bind(this, selectedRow))

        menu.Show()
    }

    CopyErrorToClipboard(*) {
        selectedRow := this.lv.GetNext(0)
        if (!selectedRow)
            return

        entry := this.lv.%"Row" selectedRow "Data"%
        if (entry && entry.Has("FullText")) {
            A_Clipboard := entry["FullText"]
            this.UpdateStatus("Copied full error details to clipboard")
        } else {
            A_Clipboard := this.lv.GetText(selectedRow, 3)
            this.UpdateStatus("Copied error message to clipboard")
        }
    }

    FilterByLevel(selectedRow, *) {
        if (!selectedRow)
            return

        level := this.lv.GetText(selectedRow, 2)

        for i, lvl in LogViewer.Config["levels"] {
            if (lvl = level) {
                this.levelCombo.Choose(i)
                this.filterLevel := level
                this.RefreshLogView()
                return
            }
        }
    }

    SearchSimilarErrors(selectedRow, *) {
        if (!selectedRow)
            return

        entry := this.lv.%"Row" selectedRow "Data"%
        if (entry && entry.Has("Type") && entry["Type"]) {
            this.searchText := entry["Type"]
            this.searchEdit.Value := this.searchText
            this.RefreshLogView()
        }
    }

    OnLevelChange(*) {
        this.filterLevel := this.levelCombo.Text
        this.RefreshLogView()
    }

    OnSearch(*) {
        this.searchText := this.searchEdit.Value
        this.RefreshLogView()
    }

    OnRefreshToggle(*) {
        this.autoRefresh := this.refreshChk.Value
    }

    OnRefreshClick(*) {
        this.ReadLogFile()
        this.RefreshLogView()
    }

    OnClearLog(*) {
        if (MsgBox("Are you sure you want to clear the log file?", "Confirm Clear", "YesNo Icon!") = "Yes") {
            try {
                FileDelete(this.logFile)
                FileAppend("", this.logFile)
                this.ReadLogFile()
                this.RefreshLogView()
                this.UpdateStatus("Log file cleared")
            } catch as err {
                this.UpdateStatus("Error clearing log file: " err.Message)
            }
        }
    }

    OnSize(guiObj, minMax, width, height) {
        if (minMax = -1)
            return

        lvWidth := width - 20
        lvHeight := height - 100

        this.lv.Move(, , lvWidth, lvHeight)
        this.statusBar.Move(, height - 25, lvWidth)

        this.lv.ModifyCol(1, 180)
        this.lv.ModifyCol(2, 80)
        this.lv.ModifyCol(3, lvWidth - 460)
        this.lv.ModifyCol(4, 150)
        this.lv.ModifyCol(5, 50)
    }

    UpdateStatus(message) {
        this.statusBar.Value := message
    }

    Show() {
        this.gui.Show("w" LogViewer.Config["defaultWidth"] " h" LogViewer.Config["defaultHeight"])
        this.RefreshLogView()
    }
}
