## Category 3: Debugger Integration & Introspection (5 examples)

### Example 21: Live Variable Inspector GUI
*Shows all variables in real-time during script execution*

```ahk
#Requires AutoHotkey v2.0

class LiveVariableInspector {
    __New() {
        this.vars := Map()
        this.gui := Gui("+AlwaysOnTop +Resize", "Variable Inspector")
        this.gui.SetFont("s9", "Consolas")
        this.lv := this.gui.Add("ListView", "r20 w600", ["Name", "Value", "Type"])
        this.lv.ModifyCol(1, 200)
        this.lv.ModifyCol(2, 300)
        this.lv.ModifyCol(3, 100)
        this.gui.Show()

        ; Auto-refresh
        SetTimer(() => this.Refresh(), 500)
    }

    Watch(name, varRef) {
        this.vars[name] := varRef
    }

    Refresh() {
        this.lv.Delete()

        for name, varRef in this.vars {
            try {
                value := %varRef%
                type := Type(value)

                ; Truncate long values
                valueStr := String(value)
                if (StrLen(valueStr) > 50)
                    valueStr := SubStr(valueStr, 1, 47) "..."

                this.lv.Add("", name, valueStr, type)
            } catch {
                this.lv.Add("", name, "<error>", "")
            }
        }
    }
}

; Usage
inspector := LiveVariableInspector()

; Watch some variables
counter := 0
status := "Running"
data := [1, 2, 3, 4, 5]

inspector.Watch("counter", "counter")
inspector.Watch("status", "status")
inspector.Watch("data", "data")

; Modify variables dynamically
SetTimer(() => {
    global counter, status
    counter++
    status := Mod(counter, 2) ? "Active" : "Idle"
}, 1000)

MsgBox("Watch variables update in real-time!")
```

---

### Example 22: Execution Profiler
*Measures function execution times and call counts*

```ahk
#Requires AutoHotkey v2.0

class ExecutionProfiler {
    __New() {
        this.functions := Map()
    }

    Profile(funcName, func) {
        this.functions[funcName] := {
            calls: 0,
            totalTime: 0,
            minTime: 9999999,
            maxTime: 0
        }

        ; Return wrapped function
        return (args*) => {
            stats := this.functions[funcName]
            stats.calls++

            startTime := A_TickCount
            result := func(args*)
            elapsed := A_TickCount - startTime

            stats.totalTime += elapsed
            stats.minTime := Min(stats.minTime, elapsed)
            stats.maxTime := Max(stats.maxTime, elapsed)

            return result
        }
    }

    GetReport() {
        report := "Function Profiling Report`n"
        report .= "==========================`n`n"

        for name, stats in this.functions {
            avg := stats.calls > 0 ? stats.totalTime / stats.calls : 0
            report .= Format("{1}:`n  Calls: {2}`n  Total: {3}ms`n  Avg: {4}ms`n  Min: {5}ms`n  Max: {6}ms`n`n",
                name, stats.calls, stats.totalTime, Round(avg, 2), stats.minTime, stats.maxTime)
        }

        return report
    }

    Reset() {
        for name, stats in this.functions {
            stats.calls := 0
            stats.totalTime := 0
            stats.minTime := 9999999
            stats.maxTime := 0
        }
    }
}

; Usage
profiler := ExecutionProfiler()

; Profile some functions
SlowFunction := profiler.Profile("SlowFunction", (n) => {
    Sleep(Random(10, 50))
    return n * 2
})

FastFunction := profiler.Profile("FastFunction", (n) => {
    return n + 1
})

; Run functions
Loop 100 {
    SlowFunction(A_Index)
    FastFunction(A_Index)
}

MsgBox(profiler.GetReport())
```

---

### Example 23: Call Stack Tracer
*Tracks function call hierarchy*

```ahk
#Requires AutoHotkey v2.0

class CallStackTracer {
    __New() {
        this.stack := []
        this.depth := 0
        this.maxDepth := 0
    }

    Enter(funcName) {
        this.depth++
        this.maxDepth := Max(this.maxDepth, this.depth)

        indent := ""
        Loop this.depth - 1
            indent .= "  "

        entry := {
            name: funcName,
            depth: this.depth,
            time: A_TickCount
        }

        this.stack.Push(entry)
        OutputDebug(indent "→ " funcName)
    }

    Exit(funcName) {
        if (this.stack.Length == 0)
            return

        entry := this.stack.Pop()
        elapsed := A_TickCount - entry.time

        indent := ""
        Loop this.depth - 1
            indent .= "  "

        OutputDebug(indent "← " funcName " (" elapsed "ms)")
        this.depth--
    }

    Trace(funcName, func) {
        return (args*) => {
            this.Enter(funcName)
            try {
                result := func(args*)
                this.Exit(funcName)
                return result
            } catch as err {
                this.Exit(funcName " [ERROR]")
                throw err
            }
        }
    }

    GetStackString() {
        str := "Call Stack:`n"
        for entry in this.stack {
            indent := ""
            Loop entry.depth - 1
                indent .= "  "
            str .= indent entry.name "`n"
        }
        return str
    }
}

; Usage
tracer := CallStackTracer()

; Wrap functions
FuncA := tracer.Trace("FuncA", () => {
    Sleep(10)
    FuncB()
})

FuncB := tracer.Trace("FuncB", () => {
    Sleep(20)
    FuncC()
})

FuncC := tracer.Trace("FuncC", () => {
    Sleep(15)
})

; Execute
FuncA()
MsgBox("Max depth: " tracer.maxDepth "`n`nCheck DebugView for trace output")
```

---

### Example 24: Memory Usage Monitor
*Tracks script memory consumption*

```ahk
#Requires AutoHotkey v2.0

class MemoryMonitor {
    __New() {
        this.samples := []
        this.maxSamples := 100

        SetTimer(() => this.Sample(), 1000)
    }

    Sample() {
        ; Get process memory info
        size := 0
        size := this.GetProcessMemory()

        this.samples.Push({
            time: A_TickCount,
            memory: size
        })

        if (this.samples.Length > this.maxSamples)
            this.samples.RemoveAt(1)
    }

    GetProcessMemory() {
        ; Get current process memory (private working set)
        static PID := ProcessExist()

        ; Use WMI query
        query := ComObject("WinMgmts:").ExecQuery(
            "SELECT WorkingSetSize FROM Win32_Process WHERE ProcessId=" PID)

        for proc in query
            return Round(proc.WorkingSetSize / 1024 / 1024, 2)  ; MB

        return 0
    }

    GetStats() {
        if (this.samples.Length == 0)
            return {current: 0, min: 0, max: 0, avg: 0}

        total := 0
        min := 999999
        max := 0

        for sample in this.samples {
            total += sample.memory
            min := Min(min, sample.memory)
            max := Max(max, sample.memory)
        }

        return {
            current: this.samples[this.samples.Length].memory,
            min: min,
            max: max,
            avg: Round(total / this.samples.Length, 2)
        }
    }

    ShowGraph() {
        gui := Gui("+AlwaysOnTop", "Memory Usage")
        edit := gui.Add("Edit", "r15 w400 ReadOnly")

        stats := this.GetStats()
        output := Format("Current: {1} MB`nMin: {2} MB`nMax: {3} MB`nAvg: {4} MB`n`nHistory:`n",
            stats.current, stats.min, stats.max, stats.avg)

        for sample in this.samples {
            bars := Round(sample.memory * 2)
            bar := ""
            Loop bars
                bar .= "█"

            output .= Format("{1} MB {2}`n", sample.memory, bar)
        }

        edit.Value := output
        gui.Show()
    }
}

; Usage
monitor := MemoryMonitor()

; Allocate some memory to test
bigArray := []
Loop 1000
    bigArray.Push(Random(1, 100))

MsgBox("Memory monitor running. Press F9 to see stats.")
F9::monitor.ShowGraph()
```

---

### Example 25: Exception Tracker
*Logs all exceptions with context*

```ahk
#Requires AutoHotkey v2.0

class ExceptionTracker {
    __New() {
        this.exceptions := []
        this.gui := ""
    }

    Track(callback) {
        return (args*) => {
            try {
                return callback(args*)
            } catch as err {
                this.LogException(err)
                throw err  ; Re-throw
            }
        }
    }

    LogException(err) {
        entry := {
            time: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            message: err.Message,
            what: err.What,
            extra: err.Extra,
            file: err.File,
            line: err.Line,
            stack: err.Stack
        }

        this.exceptions.Push(entry)

        ; Show notification
        ToolTip("Exception logged: " err.Message)
        SetTimer(() => ToolTip(), -2000)
    }

    ShowLog() {
        if (!this.gui) {
            this.gui := Gui("+Resize", "Exception Log")
            this.gui.SetFont("s9", "Consolas")
            this.lv := this.gui.Add("ListView", "r20 w800", ["Time", "Message", "File", "Line"])
            this.lv.ModifyCol(1, 150)
            this.lv.ModifyCol(2, 400)
            this.lv.ModifyCol(3, 150)
            this.lv.ModifyCol(4, 80)
        }

        this.lv.Delete()

        for entry in this.exceptions {
            this.lv.Add("", entry.time, entry.message, entry.file, entry.line)
        }

        this.gui.Show()
    }

    ExportLog(filename) {
        f := FileOpen(filename, "w")
        f.WriteLine("Exception Log")
        f.WriteLine("=============`n")

        for entry in this.exceptions {
            f.WriteLine("Time: " entry.time)
            f.WriteLine("Message: " entry.message)
            f.WriteLine("File: " entry.file ":" entry.line)
            f.WriteLine("Stack: " entry.stack)
            f.WriteLine("")
        }

        f.Close()
    }
}

; Usage
tracker := ExceptionTracker()

; Wrap risky functions
RiskyFunction := tracker.Track(() => {
    if (Random(0, 1))
        throw Error("Random error!")
    return "Success"
})

; Test it
Loop 10 {
    try {
        result := RiskyFunction()
    } catch {
        ; Exception already logged
    }
}

MsgBox("Press F8 to see exception log")
F8::tracker.ShowLog()
```

Let me continue with the overlay and advanced GUI examples...
