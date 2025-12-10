## Category 2: Quasi-Threading & Advanced Timing (10 examples)

### Example 11: Cooperative Multitasking Scheduler
*Implements time-sliced execution of multiple tasks*

```ahk
#Requires AutoHotkey v2.0

class TaskScheduler {
    __New(quantumMs := 50) {
        this.tasks := []
        this.quantum := quantumMs
        this.running := false
        this.currentTask := 0
    }

    AddTask(name, generator) {
        this.tasks.Push({
            name: name,
            gen: generator,
            state: "ready"
        })
    }

    Start() {
        this.running := true
        this.Schedule()
    }

    Schedule() {
        if (!this.running || this.tasks.Length == 0)
            return

        ; Round-robin scheduling
        this.currentTask := Mod(this.currentTask, this.tasks.Length) + 1
        task := this.tasks[this.currentTask]

        if (task.state = "ready" || task.state = "running") {
            task.state := "running"

            ; Execute task for one quantum
            startTime := A_TickCount
            try {
                result := task.gen.Call()
                if (result = "done")
                    task.state := "finished"
            } catch as err {
                task.state := "error"
                MsgBox("Task " task.name " error: " err.Message)
            }
        }

        ; Schedule next quantum
        SetTimer(() => this.Schedule(), -this.quantum)
    }

    Stop() {
        this.running := false
    }
}

; Example tasks (generators)
TaskPrinter(id) {
    count := 0
    return () => {
        if (count >= 10)
            return "done"

        ToolTip("Task " id ": " count)
        count++
        return "continue"
    }
}

TaskCounter(start, end) {
    current := start
    return () => {
        if (current > end)
            return "done"

        OutputDebug("Count: " current)
        current++
        return "continue"
    }
}

; Usage
scheduler := TaskScheduler(100)
scheduler.AddTask("Printer1", TaskPrinter(1))
scheduler.AddTask("Printer2", TaskPrinter(2))
scheduler.AddTask("Counter", TaskCounter(1, 20))
scheduler.Start()

MsgBox("Scheduler running with 3 concurrent tasks!")
```

---

### Example 12: Debouncer for Rapid Events
*Prevents function spam from rapid triggers*

```ahk
#Requires AutoHotkey v2.0

class Debouncer {
    __New(wait := 300) {
        this.wait := wait
        this.timers := Map()
    }

    ; Leading edge - execute immediately, ignore subsequent calls
    Leading(key, callback) {
        if (this.timers.Has(key))
            return  ; Still in cooldown

        callback()
        this.timers[key] := true
        SetTimer(() => this.timers.Delete(key), -this.wait)
    }

    ; Trailing edge - execute after silence period
    Trailing(key, callback) {
        if (this.timers.Has(key))
            SetTimer(this.timers[key], 0)  ; Cancel old timer

        timer := () => {
            callback()
            this.timers.Delete(key)
        }

        this.timers[key] := timer
        SetTimer(timer, -this.wait)
    }

    ; Both edges
    Both(key, callback) {
        if (!this.timers.Has(key)) {
            ; Leading: immediate execution
            callback()
        }

        ; Trailing: schedule for end
        if (this.timers.Has(key) && this.timers[key] != "leading")
            SetTimer(this.timers[key], 0)

        this.timers[key] := "leading"

        timer := () => {
            if (this.timers[key] = "leading")
                callback()  ; Trailing execution
            this.timers.Delete(key)
        }

        SetTimer(timer, -this.wait)
    }
}

; Usage
debouncer := Debouncer(500)

; Rapid key presses
^j:: {
    debouncer.Leading("search", () => {
        MsgBox("Searching... (immediate, ignores rapid presses)")
    })
}

^k:: {
    debouncer.Trailing("save", () => {
        MsgBox("Saving... (waits for pause in typing)")
    })
}

^l:: {
    debouncer.Both("refresh", () => {
        ToolTip("Refreshed at " A_Now)
        SetTimer(() => ToolTip(), -1000)
    })
}
```

---

### Example 13: Animation Frame Rate Controller
*Smooth animations with consistent frame timing*

```ahk
#Requires AutoHotkey v2.0

class AnimationController {
    __New(fps := 60) {
        this.fps := fps
        this.frameTime := 1000 / fps
        this.animations := Map()
        this.running := false
    }

    AddAnimation(name, duration, easing, callback) {
        this.animations[name] := {
            duration: duration,
            easing: easing,
            callback: callback,
            startTime: 0,
            progress: 0
        }
    }

    Start(name) {
        if (!this.animations.Has(name))
            return

        anim := this.animations[name]
        anim.startTime := A_TickCount
        anim.progress := 0

        if (!this.running) {
            this.running := true
            this.Tick()
        }
    }

    Tick() {
        if (!this.running)
            return

        currentTime := A_TickCount
        anyActive := false

        for name, anim in this.animations {
            if (anim.startTime == 0)
                continue

            elapsed := currentTime - anim.startTime
            anim.progress := Min(1.0, elapsed / anim.duration)

            ; Apply easing
            easedProgress := this.ApplyEasing(anim.progress, anim.easing)

            ; Call animation callback
            anim.callback(easedProgress)

            if (anim.progress >= 1.0) {
                anim.startTime := 0  ; Animation complete
            } else {
                anyActive := true
            }
        }

        if (anyActive) {
            SetTimer(() => this.Tick(), -this.frameTime)
        } else {
            this.running := false
        }
    }

    ApplyEasing(t, type := "linear") {
        switch type {
            case "linear":
                return t
            case "easeInQuad":
                return t * t
            case "easeOutQuad":
                return t * (2 - t)
            case "easeInOutQuad":
                return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
            case "easeInCubic":
                return t * t * t
            case "easeOutCubic":
                return (--t) * t * t + 1
        }
        return t
    }
}

; Usage - Animate GUI window
MyGui := Gui()
MyGui.Add("Text", "w200 h100 Center", "Watch me animate!")
MyGui.Show("x100 y100 w200 h100")

animator := AnimationController(60)

; Slide right animation
animator.AddAnimation("slideRight", 1000, "easeInOutQuad", (progress) => {
    x := 100 + (300 * progress)  ; Slide from 100 to 400
    MyGui.Move(x, 100)
})

; Fade animation (would need alpha, just demonstration)
animator.AddAnimation("pulse", 2000, "easeInOutQuad", (progress) => {
    size := 100 + (50 * Sin(progress * 2 * 3.14159))
    MyGui.Move(, , 200, size)
})

MsgBox("Press Enter to start animations")
animator.Start("slideRight")
Sleep(1000)
animator.Start("pulse")
```

---

### Example 14: Periodic Task Manager with Jitter
*Runs tasks periodically with randomized timing*

```ahk
#Requires AutoHotkey v2.0

class PeriodicTaskManager {
    __New() {
        this.tasks := Map()
    }

    AddTask(name, interval, jitter := 0, callback) {
        this.tasks[name] := {
            interval: interval,
            jitter: jitter,
            callback: callback,
            timer: ""
        }

        this.ScheduleTask(name)
    }

    ScheduleTask(name) {
        task := this.tasks[name]

        ; Calculate actual interval with jitter
        actualInterval := task.interval
        if (task.jitter > 0) {
            jitterAmount := Random(-task.jitter, task.jitter)
            actualInterval += jitterAmount
        }

        task.timer := () => {
            task.callback()
            this.ScheduleTask(name)  ; Reschedule
        }

        SetTimer(task.timer, -actualInterval)
    }

    RemoveTask(name) {
        if (!this.tasks.Has(name))
            return

        task := this.tasks[name]
        if (task.timer)
            SetTimer(task.timer, 0)

        this.tasks.Delete(name)
    }
}

; Usage
ptm := PeriodicTaskManager()

; Check clipboard every 5 seconds ± 1 second
ptm.AddTask("clipboard", 5000, 1000, () => {
    clip := A_Clipboard
    if (StrLen(clip) > 0)
        ToolTip("Clipboard: " SubStr(clip, 1, 50))
})

; Auto-save every 30 seconds ± 5 seconds
ptm.AddTask("autosave", 30000, 5000, () => {
    OutputDebug("Auto-save triggered at " A_Now)
})

MsgBox("Periodic tasks running with jitter!")
```

---

### Example 15: Timeout Manager for Async Operations
*Manages operation timeouts gracefully*

```ahk
#Requires AutoHotkey v2.0

class TimeoutManager {
    __New() {
        this.operations := Map()
    }

    StartOperation(name, timeoutMs, callback, timeoutCallback) {
        ; Cancel existing operation
        if (this.operations.Has(name))
            this.CancelOperation(name)

        op := {
            callback: callback,
            timeoutCallback: timeoutCallback,
            timer: "",
            completed: false
        }

        ; Set timeout
        op.timer := () => {
            if (!op.completed) {
                timeoutCallback()
                this.operations.Delete(name)
            }
        }

        SetTimer(op.timer, -timeoutMs)
        this.operations[name] := op

        ; Start the operation
        callback()
    }

    CompleteOperation(name, success := true) {
        if (!this.operations.Has(name))
            return

        op := this.operations[name]
        op.completed := true

        ; Cancel timeout
        if (op.timer)
            SetTimer(op.timer, 0)

        this.operations.Delete(name)
    }

    CancelOperation(name) {
        if (!this.operations.Has(name))
            return

        op := this.operations[name]
        if (op.timer)
            SetTimer(op.timer, 0)

        this.operations.Delete(name)
    }
}

; Usage
tm := TimeoutManager()

^t:: {  ; Ctrl+T to test
    tm.StartOperation("download",
        5000,  ; 5 second timeout
        () => {
            ToolTip("Downloading...")
            ; Simulate async download
            SetTimer(() => {
                ToolTip("Download complete!")
                tm.CompleteOperation("download")
                SetTimer(() => ToolTip(), -2000)
            }, -3000)
        },
        () => {
            ToolTip("Download timed out!")
            SetTimer(() => ToolTip(), -2000)
        }
    )
}
```

---

### Example 16: Frame-Accurate Input Timing
*Ensures input sent at exact frame boundaries*

```ahk
#Requires AutoHotkey v2.0

class FrameSyncInput {
    __New(refreshRate := 60) {
        this.frameTime := 1000 / refreshRate
        this.nextFrame := A_TickCount + this.frameTime
        this.queue := []
    }

    QueueInput(input, frame := 0) {
        this.queue.Push({input: input, frame: frame})
    }

    WaitForFrame() {
        now := A_TickCount
        wait := this.nextFrame - now

        if (wait > 0)
            DllCall("Sleep", "UInt", wait)

        this.nextFrame += this.frameTime
    }

    ExecuteQueue() {
        currentFrame := 0

        while (this.queue.Length > 0) {
            item := this.queue[1]

            ; Wait until correct frame
            while (currentFrame < item.frame) {
                this.WaitForFrame()
                currentFrame++
            }

            ; Execute input
            Send(item.input)
            this.queue.RemoveAt(1)

            this.WaitForFrame()
            currentFrame++
        }
    }
}

; Usage - Perfect combo timing for games
^g:: {
    fsi := FrameSyncInput(60)

    ; Queue frame-perfect combo
    fsi.QueueInput("{LButton}", 0)
    fsi.QueueInput("{LButton}", 10)  ; Frame 10
    fsi.QueueInput("{RButton}", 11)  ; Frame 11
    fsi.QueueInput("{Space}", 25)    ; Frame 25

    ToolTip("Executing frame-perfect combo...")
    fsi.ExecuteQueue()
    ToolTip()
}
```

---

### Example 17: Adaptive Rate Limiter
*Dynamically adjusts rate limit based on success/failure*

```ahk
#Requires AutoHotkey v2.0

class AdaptiveRateLimiter {
    __New(initialRate := 1000, minRate := 100, maxRate := 5000) {
        this.currentRate := initialRate
        this.minRate := minRate
        this.maxRate := maxRate
        this.lastCall := 0
        this.successCount := 0
        this.failureCount := 0
    }

    CanProceed() {
        now := A_TickCount
        elapsed := now - this.lastCall

        if (elapsed >= this.currentRate) {
            this.lastCall := now
            return true
        }

        return false
    }

    ReportSuccess() {
        this.successCount++
        this.failureCount := Max(0, this.failureCount - 1)

        ; Increase rate (decrease delay) on consecutive successes
        if (this.successCount >= 3) {
            this.currentRate := Max(this.minRate, this.currentRate * 0.9)
            this.successCount := 0
        }
    }

    ReportFailure() {
        this.failureCount++
        this.successCount := 0

        ; Decrease rate (increase delay) on failure
        this.currentRate := Min(this.maxRate, this.currentRate * 1.5)
    }

    GetCurrentRate() {
        return this.currentRate
    }
}

; Usage - API calls with adaptive rate limiting
limiter := AdaptiveRateLimiter(1000)

^r:: {  ; Ctrl+R to test API call
    if (!limiter.CanProceed()) {
        ToolTip("Rate limited! Wait " Round(limiter.GetCurrentRate()/1000, 1) "s")
        SetTimer(() => ToolTip(), -1000)
        return
    }

    ; Simulate API call
    success := Random(0, 1)

    if (success) {
        limiter.ReportSuccess()
        ToolTip("API Success! Rate: " Round(limiter.GetCurrentRate()) "ms")
    } else {
        limiter.ReportFailure()
        ToolTip("API Failure! Rate increased to: " Round(limiter.GetCurrentRate()) "ms")
    }

    SetTimer(() => ToolTip(), -2000)
}
```

---

### Example 18: Watchdog Timer for Hung Operations
*Detects and recovers from hung operations*

```ahk
#Requires AutoHotkey v2.0

class WatchdogTimer {
    __New(timeoutMs := 5000) {
        this.timeout := timeoutMs
        this.lastKick := 0
        this.active := false
        this.onTimeout := ""
    }

    Start(onTimeout) {
        this.lastKick := A_TickCount
        this.active := true
        this.onTimeout := onTimeout

        this.Check()
    }

    Kick() {
        this.lastKick := A_TickCount
    }

    Check() {
        if (!this.active)
            return

        elapsed := A_TickCount - this.lastKick

        if (elapsed >= this.timeout) {
            ; Timeout occurred
            this.active := false
            if (this.onTimeout)
                this.onTimeout()
        } else {
            ; Schedule next check
            SetTimer(() => this.Check(), -1000)
        }
    }

    Stop() {
        this.active := false
    }
}

; Usage
watchdog := WatchdogTimer(5000)

^w:: {  ; Start monitored operation
    watchdog.Start(() => {
        MsgBox("Operation timed out! System may be hung.")
        ; Recovery actions here
    })

    ; Simulate long operation with periodic kicks
    Loop 10 {
        Sleep(400)
        watchdog.Kick()  ; Signal we're still alive
        ToolTip("Working... " A_Index "/10")
    }

    watchdog.Stop()
    ToolTip("Operation complete!")
    SetTimer(() => ToolTip(), -2000)
}
```

---

### Example 19: Event Loop with Priority Queue
*Processes events based on priority*

```ahk
#Requires AutoHotkey v2.0

class PriorityEventLoop {
    __New() {
        this.queue := []
        this.running := false
    }

    QueueEvent(priority, callback) {
        this.queue.Push({priority: priority, callback: callback})
        this.SortQueue()

        if (!this.running)
            this.ProcessQueue()
    }

    SortQueue() {
        ; Sort by priority (higher first)
        n := this.queue.Length
        Loop n - 1 {
            i := A_Index
            Loop n - i {
                j := A_Index
                if (this.queue[j].priority < this.queue[j+1].priority) {
                    temp := this.queue[j]
                    this.queue[j] := this.queue[j+1]
                    this.queue[j+1] := temp
                }
            }
        }
    }

    ProcessQueue() {
        if (this.queue.Length == 0) {
            this.running := false
            return
        }

        this.running := true

        ; Process highest priority event
        event := this.queue.RemoveAt(1)
        event.callback()

        ; Continue processing
        SetTimer(() => this.ProcessQueue(), -10)
    }
}

; Usage
loop := PriorityEventLoop()

^1:: loop.QueueEvent(1, () => ToolTip("Low priority"))
^2:: loop.QueueEvent(5, () => ToolTip("Medium priority"))
^3:: loop.QueueEvent(10, () => ToolTip("High priority"))

MsgBox("Press Ctrl+1/2/3 in any order, high priority executes first!")
```

---

### Example 20: State Machine with Timed Transitions
*Implements state machine with automatic transitions*

```ahk
#Requires AutoHotkey v2.0

class TimedStateMachine {
    __New() {
        this.currentState := "idle"
        this.states := Map()
        this.transitions := []
    }

    AddState(name, onEnter := "", onExit := "") {
        this.states[name] := {
            onEnter: onEnter,
            onExit: onExit
        }
    }

    AddTimedTransition(fromState, toState, delayMs) {
        this.transitions.Push({
            from: fromState,
            to: toState,
            delay: delayMs,
            timer: ""
        })
    }

    SetState(newState) {
        if (!this.states.Has(newState))
            return

        oldState := this.currentState

        ; Exit old state
        if (this.states.Has(oldState) && this.states[oldState].onExit)
            this.states[oldState].onExit()

        ; Cancel old state's timers
        for trans in this.transitions {
            if (trans.from = oldState && trans.timer)
                SetTimer(trans.timer, 0)
        }

        ; Enter new state
        this.currentState := newState
        if (this.states[newState].onEnter)
            this.states[newState].onEnter()

        ; Setup new state's timers
        for trans in this.transitions {
            if (trans.from = newState) {
                trans.timer := () => this.SetState(trans.to)
                SetTimer(trans.timer, -trans.delay)
            }
        }
    }
}

; Usage - Traffic light simulation
light := TimedStateMachine()

light.AddState("green",
    () => ToolTip("🟢 GREEN - GO"),
    () => {})

light.AddState("yellow",
    () => ToolTip("🟡 YELLOW - CAUTION"),
    () => {})

light.AddState("red",
    () => ToolTip("🔴 RED - STOP"),
    () => {})

light.AddTimedTransition("green", "yellow", 5000)
light.AddTimedTransition("yellow", "red", 2000)
light.AddTimedTransition("red", "green", 5000)

light.SetState("green")
MsgBox("Traffic light state machine running!")
```

Continuing with remaining categories in next files...
