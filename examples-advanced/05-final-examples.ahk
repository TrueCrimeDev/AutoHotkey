## Category 5: Memory & Process Manipulation (5 examples)

### Example 36: Process Memory Scanner
*Scans process memory for specific values*

```ahk
#Requires AutoHotkey v2.0

class MemoryScanner {
    __New(processName) {
        this.pid := ProcessExist(processName)
        if (!this.pid)
            throw Error("Process not found: " processName)

        ; Open process with read rights
        this.hProcess := DllCall("OpenProcess", "UInt", 0x0010, "Int", 0, "UInt", this.pid, "Ptr")
        if (!this.hProcess)
            throw Error("Failed to open process")
    }

    ScanForValue(value, dataType := "Int") {
        results := []

        ; Get process memory info
        mbi := Buffer(48, 0)
        address := 0

        while (address < 0x7FFFFFFF) {
            ; Query memory region
            if (!DllCall("VirtualQueryEx", "Ptr", this.hProcess, "Ptr", address, "Ptr", mbi, "UInt", 48))
                break

            baseAddr := NumGet(mbi, 0, "Ptr")
            regionSize := NumGet(mbi, 8, "UPtr")
            protect := NumGet(mbi, 20, "UInt")
            state := NumGet(mbi, 16, "UInt")

            ; Check if readable
            if (state = 0x1000 && (protect & 0xF0) == 0) {  ; MEM_COMMIT and readable
                buffer := Buffer(regionSize, 0)

                if (DllCall("ReadProcessMemory", "Ptr", this.hProcess, "Ptr", baseAddr,
                           "Ptr", buffer, "UPtr", regionSize, "UPtr*", &bytesRead := 0)) {

                    ; Scan buffer for value
                    Loop (regionSize - 4) {
                        scanValue := NumGet(buffer, A_Index - 1, dataType)
                        if (scanValue = value) {
                            results.Push(baseAddr + A_Index - 1)
                            if (results.Length >= 100)  ; Limit results
                                break 2
                        }
                    }
                }
            }

            address := baseAddr + regionSize
        }

        return results
    }

    ReadMemory(address, dataType := "Int") {
        buffer := Buffer(8, 0)
        if (DllCall("ReadProcessMemory", "Ptr", this.hProcess, "Ptr", address,
                   "Ptr", buffer, "UPtr", 8, "UPtr*", &bytesRead := 0)) {
            return NumGet(buffer, 0, dataType)
        }
        return 0
    }

    WriteMemory(address, value, dataType := "Int") {
        buffer := Buffer(8, 0)
        NumPut(dataType, value, buffer, 0)
        return DllCall("WriteProcessMemory", "Ptr", this.hProcess, "Ptr", address,
                      "Ptr", buffer, "UPtr", 8, "UPtr*", &bytesWritten := 0)
    }

    __Delete() {
        if (this.hProcess)
            DllCall("CloseHandle", "Ptr", this.hProcess)
    }
}

; Usage
try {
    scanner := MemoryScanner("notepad.exe")
    MsgBox("Memory scanner ready for notepad.exe")

    ; Example: Scan for value 42
    ; addresses := scanner.ScanForValue(42)
    ; MsgBox("Found " addresses.Length " occurrences")
} catch as err {
    MsgBox("Error: " err.Message)
}
```

---

### Example 37: DLL Injector
*Injects DLL into target process*

```ahk
#Requires AutoHotkey v2.0

class DllInjector {
    static Inject(processName, dllPath) {
        ; Get process ID
        pid := ProcessExist(processName)
        if (!pid)
            throw Error("Process not found: " processName)

        ; Open process
        hProcess := DllCall("OpenProcess",
            "UInt", 0x001F0FFF,  ; PROCESS_ALL_ACCESS
            "Int", 0,
            "UInt", pid,
            "Ptr")

        if (!hProcess)
            throw Error("Failed to open process")

        try {
            ; Allocate memory in target process
            dllPathLen := StrLen(dllPath) + 1
            pRemotePath := DllCall("VirtualAllocEx",
                "Ptr", hProcess,
                "Ptr", 0,
                "UPtr", dllPathLen,
                "UInt", 0x3000,  ; MEM_COMMIT | MEM_RESERVE
                "UInt", 0x04,    ; PAGE_READWRITE
                "Ptr")

            if (!pRemotePath)
                throw Error("Failed to allocate memory")

            ; Write DLL path
            if (!DllCall("WriteProcessMemory",
                        "Ptr", hProcess,
                        "Ptr", pRemotePath,
                        "Str", dllPath,
                        "UPtr", dllPathLen,
                        "UPtr*", 0))
                throw Error("Failed to write DLL path")

            ; Get LoadLibraryA address
            hKernel32 := DllCall("GetModuleHandle", "Str", "kernel32.dll", "Ptr")
            pLoadLibrary := DllCall("GetProcAddress", "Ptr", hKernel32, "AStr", "LoadLibraryA", "Ptr")

            ; Create remote thread
            hThread := DllCall("CreateRemoteThread",
                "Ptr", hProcess,
                "Ptr", 0,
                "UPtr", 0,
                "Ptr", pLoadLibrary,
                "Ptr", pRemotePath,
                "UInt", 0,
                "UInt*", 0,
                "Ptr")

            if (!hThread)
                throw Error("Failed to create remote thread")

            ; Wait for thread
            DllCall("WaitForSingleObject", "Ptr", hThread, "UInt", -1)
            DllCall("CloseHandle", "Ptr", hThread)

            return true
        } finally {
            DllCall("CloseHandle", "Ptr", hProcess)
        }
    }
}

; Usage (CAUTION: Use only for legitimate purposes)
; DllInjector.Inject("notepad.exe", "C:\path\to\your.dll")
MsgBox("DLL Injection example (educational purpose only)")
```

---

### Example 38: Process Hollowing (Concept)
*Demonstrates process hollowing technique*

```ahk
#Requires AutoHotkey v2.0

class ProcessHollowing {
    ; EDUCATIONAL ONLY - Shows technique concept
    static HollowProcess(targetExe, payloadPath) {
        ; Create suspended process
        si := Buffer(68, 0)
        pi := Buffer(24, 0)
        NumPut("UInt", 68, si, 0)

        if (!DllCall("CreateProcess",
                    "Ptr", 0,
                    "Str", targetExe,
                    "Ptr", 0, "Ptr", 0, "Int", 0,
                    "UInt", 0x04,  ; CREATE_SUSPENDED
                    "Ptr", 0, "Ptr", 0,
                    "Ptr", si, "Ptr", pi))
            throw Error("Failed to create process")

        hProcess := NumGet(pi, 0, "Ptr")
        hThread := NumGet(pi, 8, "Ptr")

        ; Get process context
        context := Buffer(716, 0)
        NumPut("UInt", 0x10007, context, 0)  ; CONTEXT_FULL

        if (!DllCall("GetThreadContext", "Ptr", hThread, "Ptr", context))
            throw Error("Failed to get context")

        ; Read PEB address
        pebAddr := NumGet(context, 168, "Ptr")  ; Rdx on x64

        ; The rest would involve:
        ; 1. Unmapping original image
        ; 2. Allocating new memory
        ; 3. Writing payload
        ; 4. Adjusting entry point
        ; 5. Resuming thread

        MsgBox("Process hollowing concept demonstrated`nProcess created in suspended state")

        ; Cleanup
        DllCall("TerminateProcess", "Ptr", hProcess, "UInt", 0)
        DllCall("CloseHandle", "Ptr", hProcess)
        DllCall("CloseHandle", "Ptr", hThread)
    }
}

; This is educational only
MsgBox("Process Hollowing concept example`nFor educational purposes only!")
```

---

### Example 39: Memory Pattern Finder
*Finds patterns in process memory (like Cheat Engine)*

```ahk
#Requires AutoHotkey v2.0

class PatternFinder {
    __New(processName) {
        this.pid := ProcessExist(processName)
        this.hProcess := DllCall("OpenProcess", "UInt", 0x0010, "Int", 0, "UInt", this.pid, "Ptr")
    }

    FindPattern(pattern, mask) {
        ; Pattern: array of bytes
        ; Mask: string like "xxx?x" where ? is wildcard

        results := []
        address := 0

        while (address < 0x7FFFFFFF) {
            ; Read chunk of memory
            buffer := Buffer(4096, 0)

            if (DllCall("ReadProcessMemory", "Ptr", this.hProcess, "Ptr", address,
                       "Ptr", buffer, "UPtr", 4096, "UPtr*", &bytesRead := 0)) {

                ; Scan for pattern
                Loop (bytesRead - pattern.Length) {
                    match := true

                    for i, byte in pattern {
                        maskChar := SubStr(mask, i, 1)
                        if (maskChar != "?" && NumGet(buffer, A_Index + i - 2, "UChar") != byte) {
                            match := false
                            break
                        }
                    }

                    if (match) {
                        results.Push(address + A_Index - 1)
                        if (results.Length >= 10)
                            return results
                    }
                }
            }

            address += 4096
        }

        return results
    }

    __Delete() {
        if (this.hProcess)
            DllCall("CloseHandle", "Ptr", this.hProcess)
    }
}

; Usage
; finder := PatternFinder("game.exe")
; pattern := [0x48, 0x8B, 0xC4, 0x48, 0x89]  ; mov rax, rsp; mov...
; mask := "xxxxx"
; addresses := finder.FindPattern(pattern, mask)
MsgBox("Pattern finder example (like Cheat Engine)")
```

---

### Example 40: Process Environment Block (PEB) Reader
*Reads PEB structure from process*

```ahk
#Requires AutoHotkey v2.0

class PEBReader {
    static ReadPEB(pid) {
        ; Open process
        hProcess := DllCall("OpenProcess",
            "UInt", 0x0410,  ; QUERY_INFORMATION | VM_READ
            "Int", 0,
            "UInt", pid,
            "Ptr")

        if (!hProcess)
            throw Error("Failed to open process")

        try {
            ; Get basic process information
            pbi := Buffer(48, 0)
            status := DllCall("ntdll\NtQueryInformationProcess",
                "Ptr", hProcess,
                "UInt", 0,  ; ProcessBasicInformation
                "Ptr", pbi,
                "UInt", 48,
                "UInt*", 0)

            if (status != 0)
                throw Error("NtQueryInformationProcess failed")

            pebAddress := NumGet(pbi, A_PtrSize * 2, "Ptr")

            ; Read PEB
            peb := Buffer(512, 0)
            if (!DllCall("ReadProcessMemory",
                        "Ptr", hProcess,
                        "Ptr", pebAddress,
                        "Ptr", peb,
                        "UPtr", 512,
                        "UPtr*", 0))
                throw Error("Failed to read PEB")

            ; Extract information
            info := Map()
            info["PEBAddress"] := Format("0x{:X}", pebAddress)
            info["ImageBaseAddress"] := Format("0x{:X}", NumGet(peb, A_PtrSize * 2, "Ptr"))
            info["ProcessHeap"] := Format("0x{:X}", NumGet(peb, A_PtrSize * 3, "Ptr"))

            return info
        } finally {
            DllCall("CloseHandle", "Ptr", hProcess)
        }
    }
}

; Usage
pid := ProcessExist("notepad.exe")
if (pid) {
    info := PEBReader.ReadPEB(pid)
    output := "PEB Information:`n"
    for key, value in info
        output .= key ": " value "`n"
    MsgBox(output)
}
```

---

## Category 6: WinAPI Integration (5 examples)

### Example 41: Low-Level Keyboard Hook
*Implements global keyboard hook*

```ahk
#Requires AutoHotkey v2.0

class LowLevelKeyboardHook {
    __New(callback) {
        this.callback := callback
        this.hHook := 0

        ; Install hook
        this.Install()
    }

    Install() {
        ; WH_KEYBOARD_LL = 13
        this.hookProc := CallbackCreate(ObjBindMethod(this, "HookCallback"), "F", 3)

        this.hHook := DllCall("SetWindowsHookEx",
            "Int", 13,  ; WH_KEYBOARD_LL
            "Ptr", this.hookProc,
            "Ptr", DllCall("GetModuleHandle", "Ptr", 0, "Ptr"),
            "UInt", 0,
            "Ptr")

        if (!this.hHook)
            throw Error("Failed to install hook")
    }

    HookCallback(nCode, wParam, lParam) {
        if (nCode >= 0) {
            vkCode := NumGet(lParam + 0, 0, "UInt")
            scanCode := NumGet(lParam + 0, 4, "UInt")
            flags := NumGet(lParam + 0, 8, "UInt")

            isKeyDown := (wParam = 0x0100 || wParam = 0x0104)  ; WM_KEYDOWN or WM_SYSKEYDOWN

            ; Call user callback
            suppress := this.callback(vkCode, scanCode, isKeyDown)

            if (suppress)
                return 1  ; Suppress key
        }

        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam)
    }

    Uninstall() {
        if (this.hHook) {
            DllCall("UnhookWindowsHookEx", "Ptr", this.hHook)
            CallbackFree(this.hookProc)
            this.hHook := 0
        }
    }

    __Delete() {
        this.Uninstall()
    }
}

; Usage
hook := LowLevelKeyboardHook((vk, sc, isDown) => {
    if (isDown && vk = 0x41) {  ; 'A' key
        ToolTip("A key pressed!")
        SetTimer(() => ToolTip(), -500)
        ; return true  ; Uncomment to suppress
    }
    return false
})

MsgBox("Low-level hook installed! Press 'A' key")
```

---

### Example 42: Mouse Event Synthesizer
*Sends realistic mouse input using SendInput*

```ahk
#Requires AutoHotkey v2.0

class MouseSynthesizer {
    static SendMouseInput(x, y, flags) {
        ; MOUSEINPUT structure
        input := Buffer(28, 0)

        ; Type = 0 (INPUT_MOUSE)
        NumPut("UInt", 0, input, 0)

        ; Convert screen coords to absolute
        screenWidth := SysGet(16)
        screenHeight := SysGet(17)
        absX := Round((x * 65536) / screenWidth)
        absY := Round((y * 65536) / screenHeight)

        ; dx, dy
        NumPut("Int", absX, input, 4)
        NumPut("Int", absY, input, 8)

        ; mouseData
        NumPut("UInt", 0, input, 12)

        ; dwFlags - ABSOLUTE | flags
        NumPut("UInt", 0x8000 | flags, input, 16)

        ; time
        NumPut("UInt", 0, input, 20)

        ; Send input
        return DllCall("SendInput", "UInt", 1, "Ptr", input, "Int", 28)
    }

    static Click(x, y, button := "left") {
        flags := 0

        switch button {
            case "left":
                this.SendMouseInput(x, y, 0x0002)  ; MOUSEEVENTF_LEFTDOWN
                this.SendMouseInput(x, y, 0x0004)  ; MOUSEEVENTF_LEFTUP
            case "right":
                this.SendMouseInput(x, y, 0x0008)  ; MOUSEEVENTF_RIGHTDOWN
                this.SendMouseInput(x, y, 0x0010)  ; MOUSEEVENTF_RIGHTUP
        }
    }

    static Move(x, y) {
        this.SendMouseInput(x, y, 0x0001)  ; MOUSEEVENTF_MOVE
    }

    static SmoothMove(startX, startY, endX, endY, duration := 1000) {
        steps := 50
        stepDelay := duration / steps

        Loop steps {
            progress := A_Index / steps
            x := startX + (endX - startX) * progress
            y := startY + (endY - startY) * progress

            this.Move(x, y)
            Sleep(stepDelay)
        }
    }
}

; Usage
^!m:: {
    MouseGetPos(&x, &y)
    MouseSynthesizer.SmoothMove(x, y, x + 200, y + 200, 500)
}
```

---

### Example 43: Window Message Interceptor
*Intercepts messages sent to windows*

```ahk
#Requires AutoHotkey v2.0

class MessageInterceptor {
    __New(hwnd) {
        this.hwnd := hwnd
        this.originalProc := 0
        this.newProc := 0
        this.messages := Map()

        this.Install()
    }

    Install() {
        ; Subclass window
        this.newProc := CallbackCreate(ObjBindMethod(this, "WindowProc"), "F", 4)

        this.originalProc := DllCall("SetWindowLongPtr",
            "Ptr", this.hwnd,
            "Int", -4,  ; GWLP_WNDPROC
            "Ptr", this.newProc,
            "Ptr")
    }

    WindowProc(hwnd, msg, wParam, lParam) {
        ; Call registered handlers
        if (this.messages.Has(msg)) {
            try {
                result := this.messages[msg](wParam, lParam)
                if (result != "")
                    return result
            }
        }

        ; Call original
        return DllCall("CallWindowProc",
            "Ptr", this.originalProc,
            "Ptr", hwnd,
            "UInt", msg,
            "Ptr", wParam,
            "Ptr", lParam)
    }

    OnMessage(msg, callback) {
        this.messages[msg] := callback
    }

    Uninstall() {
        if (this.originalProc) {
            DllCall("SetWindowLongPtr",
                "Ptr", this.hwnd,
                "Int", -4,
                "Ptr", this.originalProc,
                "Ptr")

            CallbackFree(this.newProc)
        }
    }

    __Delete() {
        this.Uninstall()
    }
}

; Usage
hwnd := WinGetID("A")
if (hwnd) {
    interceptor := MessageInterceptor(hwnd)

    ; Intercept WM_CLOSE
    interceptor.OnMessage(0x0010, (wp, lp) => {
        result := MsgBox("Really close?", , "YN")
        if (result = "No")
            return 0  ; Block close
        return ""  ; Allow
    })

    MsgBox("Try closing the active window - you'll be prompted!")
}
```

---

### Example 44: Raw Input Device Reader
*Reads raw input from HID devices*

```ahk
#Requires AutoHotkey v2.0

class RawInputReader {
    __New() {
        this.hwnd := 0
        this.devices := Map()

        this.CreateMessageWindow()
        this.RegisterDevices()
    }

    CreateMessageWindow() {
        ; Create hidden window for messages
        this.hwnd := DllCall("CreateWindowEx",
            "UInt", 0,
            "Str", "Static",
            "Str", "RawInputWindow",
            "UInt", 0,
            "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0,
            "Ptr")

        ; Set window proc
        this.wndProc := CallbackCreate(ObjBindMethod(this, "WindowProc"), "F", 4)
        DllCall("SetWindowLongPtr", "Ptr", this.hwnd, "Int", -4, "Ptr", this.wndProc, "Ptr")
    }

    RegisterDevices() {
        ; Register for raw input
        rid := Buffer(16, 0)

        ; Keyboard
        NumPut("UShort", 1, rid, 0)      ; usUsagePage
        NumPut("UShort", 6, rid, 2)      ; usUsage
        NumPut("UInt", 0x00000100, rid, 4)  ; dwFlags - RIDEV_INPUTSINK
        NumPut("Ptr", this.hwnd, rid, 8)  ; hwndTarget

        DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", 16)
    }

    WindowProc(hwnd, msg, wParam, lParam) {
        if (msg = 0x00FF) {  ; WM_INPUT
            ; Get raw input size
            size := 0
            DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
                   "Ptr", 0, "UInt*", &size, "UInt", 16)

            ; Allocate buffer
            buffer := Buffer(size, 0)

            ; Get data
            if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
                       "Ptr", buffer, "UInt*", &size, "UInt", 16) = size) {

                ; Parse header
                type := NumGet(buffer, 0, "UInt")

                if (type = 0) {  ; RIM_TYPEMOUSE
                    this.OnMouseInput(buffer)
                } else if (type = 1) {  ; RIM_TYPEKEYBOARD
                    this.OnKeyboardInput(buffer)
                }
            }
        }

        return DllCall("DefWindowProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam)
    }

    OnMouseInput(buffer) {
        ; Parse RAWMOUSE structure
        flags := NumGet(buffer, 16, "UShort")
        buttonFlags := NumGet(buffer, 24, "UShort")
        lastX := NumGet(buffer, 32, "Int")
        lastY := NumGet(buffer, 36, "Int")

        OutputDebug("Raw Mouse: " lastX ", " lastY)
    }

    OnKeyboardInput(buffer) {
        ; Parse RAWKEYBOARD structure
        makeCode := NumGet(buffer, 16, "UShort")
        flags := NumGet(buffer, 18, "UShort")
        vKey := NumGet(buffer, 22, "UShort")

        OutputDebug("Raw Keyboard: VK=" vKey " Make=" makeCode)
    }
}

; Usage
reader := RawInputReader()
MsgBox("Raw input reader active! Check DebugView for output")
```

---

### Example 45: System Tray Icon Manager
*Creates and manages system tray icons*

```ahk
#Requires AutoHotkey v2.0

class TrayIconManager {
    __New() {
        this.icons := Map()
        this.nextId := 1
    }

    AddIcon(iconFile, tooltip := "") {
        id := this.nextId++

        ; Load icon
        hIcon := DllCall("LoadImage",
            "Ptr", 0,
            "Str", iconFile,
            "UInt", 1,  ; IMAGE_ICON
            "Int", 0, "Int", 0,
            "UInt", 0x00000010,  ; LR_LOADFROMFILE
            "Ptr")

        if (!hIcon)
            throw Error("Failed to load icon")

        ; NOTIFYICONDATA structure
        nid := Buffer(504, 0)
        NumPut("UInt", 504, nid, 0)  ; cbSize
        NumPut("Ptr", A_ScriptHwnd, nid, 4)  ; hWnd
        NumPut("UInt", id, nid, 8)  ; uID
        NumPut("UInt", 0x00000007, nid, 12)  ; uFlags (NIF_MESSAGE | NIF_ICON | NIF_TIP)
        NumPut("UInt", 0x8000, nid, 16)  ; uCallbackMessage
        NumPut("Ptr", hIcon, nid, 20)  ; hIcon

        ; Set tooltip
        if (tooltip)
            StrPut(tooltip, nid.Ptr + 28, 128, "UTF-16")

        ; Add icon
        DllCall("shell32\Shell_NotifyIcon", "UInt", 0, "Ptr", nid)

        this.icons[id] := {nid: nid, hIcon: hIcon}
        return id
    }

    RemoveIcon(id) {
        if (!this.icons.Has(id))
            return

        icon := this.icons[id]
        DllCall("shell32\Shell_NotifyIcon", "UInt", 2, "Ptr", icon.nid)
        DllCall("DestroyIcon", "Ptr", icon.hIcon)
        this.icons.Delete(id)
    }

    UpdateIcon(id, newIconFile) {
        if (!this.icons.Has(id))
            return

        ; Load new icon
        hIcon := DllCall("LoadImage",
            "Ptr", 0,
            "Str", newIconFile,
            "UInt", 1,
            "Int", 0, "Int", 0,
            "UInt", 0x00000010,
            "Ptr")

        if (!hIcon)
            return

        ; Update
        icon := this.icons[id]
        NumPut("Ptr", hIcon, icon.nid, 20)
        DllCall("shell32\Shell_NotifyIcon", "UInt", 1, "Ptr", icon.nid)

        ; Destroy old icon
        DllCall("DestroyIcon", "Ptr", icon.hIcon)
        icon.hIcon := hIcon
    }
}

; Usage
; tim := TrayIconManager()
; id := tim.AddIcon("C:\path\to\icon.ico", "My Custom Icon")
MsgBox("Tray icon manager example")
```

---

## Category 7: Event System & Callbacks (5 examples)

### Example 46: Event Emitter Pattern
*Implements Node.js-style event emitter*

```ahk
#Requires AutoHotkey v2.0

class EventEmitter {
    __New() {
        this.events := Map()
    }

    On(eventName, callback) {
        if (!this.events.Has(eventName))
            this.events[eventName] := []

        this.events[eventName].Push(callback)
        return this  ; Chainable
    }

    Once(eventName, callback) {
        wrapper := (args*) => {
            callback(args*)
            this.Off(eventName, wrapper)
        }
        return this.On(eventName, wrapper)
    }

    Off(eventName, callback := "") {
        if (!this.events.Has(eventName))
            return this

        if (callback = "") {
            ; Remove all listeners
            this.events.Delete(eventName)
        } else {
            ; Remove specific listener
            listeners := this.events[eventName]
            for i, cb in listeners {
                if (cb = callback) {
                    listeners.RemoveAt(i)
                    break
                }
            }
        }

        return this
    }

    Emit(eventName, args*) {
        if (!this.events.Has(eventName))
            return false

        for callback in this.events[eventName] {
            try {
                callback(args*)
            } catch as err {
                OutputDebug("Event handler error: " err.Message)
            }
        }

        return true
    }

    ListenerCount(eventName) {
        return this.events.Has(eventName) ? this.events[eventName].Length : 0
    }
}

; Usage
emitter := EventEmitter()

; Register multiple handlers
emitter.On("data", (data) => ToolTip("Handler 1: " data))
emitter.On("data", (data) => OutputDebug("Handler 2: " data))
emitter.Once("end", () => MsgBox("Ended!"))

; Emit events
emitter.Emit("data", "Hello World")
emitter.Emit("data", "Second message")
emitter.Emit("end")  ; Only fires once

MsgBox("Check tooltip and DebugView for output")
```

---

### Example 47: Promise-Like Async Pattern
*Implements promise-style async operations*

```ahk
#Requires AutoHotkey v2.0

class Promise {
    __New(executor) {
        this.state := "pending"  ; pending, fulfilled, rejected
        this.value := ""
        this.handlers := []

        try {
            executor(
                ObjBindMethod(this, "Resolve"),
                ObjBindMethod(this, "Reject")
            )
        } catch as err {
            this.Reject(err)
        }
    }

    Resolve(value) {
        if (this.state != "pending")
            return

        this.state := "fulfilled"
        this.value := value

        for handler in this.handlers {
            if (handler.Has("onFulfilled"))
                SetTimer(() => handler["onFulfilled"](value), -1)
        }
    }

    Reject(reason) {
        if (this.state != "pending")
            return

        this.state := "rejected"
        this.value := reason

        for handler in this.handlers {
            if (handler.Has("onRejected"))
                SetTimer(() => handler["onRejected"](reason), -1)
        }
    }

    Then(onFulfilled, onRejected := "") {
        newPromise := Promise((resolve, reject) => {
            handler := Map()

            if (onFulfilled) {
                handler["onFulfilled"] := (value) => {
                    try {
                        result := onFulfilled(value)
                        resolve(result)
                    } catch as err {
                        reject(err)
                    }
                }
            }

            if (onRejected) {
                handler["onRejected"] := (reason) => {
                    try {
                        result := onRejected(reason)
                        resolve(result)
                    } catch as err {
                        reject(err)
                    }
                }
            }

            if (this.state = "pending") {
                this.handlers.Push(handler)
            } else if (this.state = "fulfilled" && handler.Has("onFulfilled")) {
                SetTimer(() => handler["onFulfilled"](this.value), -1)
            } else if (this.state = "rejected" && handler.Has("onRejected")) {
                SetTimer(() => handler["onRejected"](this.value), -1)
            }
        })

        return newPromise
    }

    Catch(onRejected) {
        return this.Then("", onRejected)
    }
}

; Usage
promise := Promise((resolve, reject) => {
    ; Simulate async operation
    SetTimer(() => {
        if (Random(0, 1))
            resolve("Success!")
        else
            reject("Failed!")
    }, -2000)
})

promise.Then((value) => {
    MsgBox("Resolved: " value)
}).Catch((reason) => {
    MsgBox("Rejected: " reason)
})

MsgBox("Promise created - waiting 2 seconds...")
```

---

### Example 48: Observer Pattern
*Subject-Observer implementation*

```ahk
#Requires AutoHotkey v2.0

class Subject {
    __New() {
        this.observers := []
    }

    Attach(observer) {
        this.observers.Push(observer)
    }

    Detach(observer) {
        for i, obs in this.observers {
            if (obs = observer) {
                this.observers.RemoveAt(i)
                return
            }
        }
    }

    Notify(data := "") {
        for observer in this.observers {
            observer.Update(this, data)
        }
    }
}

class Observer {
    Update(subject, data) {
        ; Override in subclass
        MsgBox("Observer notified with: " data)
    }
}

; Example: Temperature Monitor
class TemperatureMonitor extends Subject {
    __New() {
        super.__New()
        this.temperature := 20
    }

    SetTemperature(temp) {
        this.temperature := temp
        this.Notify(temp)
    }

    GetTemperature() {
        return this.temperature
    }
}

class DisplayObserver extends Observer {
    Update(subject, data) {
        ToolTip("Temperature: " data "°C")
        SetTimer(() => ToolTip(), -2000)
    }
}

class LogObserver extends Observer {
    Update(subject, data) {
        FormatTime, timeStr, , "yyyy-MM-dd HH:mm:ss"
        OutputDebug(timeStr " - Temperature: " data "°C")
    }
}

class AlertObserver extends Observer {
    Update(subject, data) {
        if (data > 30)
            MsgBox("WARNING: High temperature! " data "°C")
    }
}

; Usage
monitor := TemperatureMonitor()
monitor.Attach(DisplayObserver())
monitor.Attach(LogObserver())
monitor.Attach(AlertObserver())

; Change temperature
monitor.SetTemperature(25)
Sleep(1000)
monitor.SetTemperature(35)  ; Triggers alert
```

---

### Example 49: Middleware Pipeline
*Chain of responsibility with middleware*

```ahk
#Requires AutoHotkey v2.0

class MiddlewarePipeline {
    __New() {
        this.middlewares := []
    }

    Use(middleware) {
        this.middlewares.Push(middleware)
        return this  ; Chainable
    }

    Execute(context) {
        index := 1

        next := () => {
            if (index > this.middlewares.Length)
                return

            middleware := this.middlewares[index]
            index++

            try {
                middleware(context, next)
            } catch as err {
                throw Error("Middleware error: " err.Message)
            }
        }

        next()
        return context
    }
}

; Usage
pipeline := MiddlewarePipeline()

; Add middleware
pipeline.Use((ctx, next) => {
    ctx["logged"] := true
    OutputDebug("Middleware 1: Logging request")
    next()
    OutputDebug("Middleware 1: Complete")
})

pipeline.Use((ctx, next) => {
    if (!ctx["authenticated"]) {
        throw Error("Not authenticated!")
    }
    OutputDebug("Middleware 2: Authenticated")
    next()
})

pipeline.Use((ctx, next) => {
    ctx["result"] := "Success"
    OutputDebug("Middleware 3: Processing")
    next()
})

; Execute pipeline
context := Map("authenticated", true)
try {
    pipeline.Execute(context)
    MsgBox("Result: " context["result"])
} catch as err {
    MsgBox("Error: " err.Message)
}
```

---

### Example 50: Reactive State Manager
*Reactive programming pattern (like Vue/React)*

```ahk
#Requires AutoHotkey v2.0

class ReactiveState {
    __New(initialState) {
        this.state := initialState
        this.watchers := Map()
    }

    Get(key) {
        return this.state.Has(key) ? this.state[key] : ""
    }

    Set(key, value) {
        oldValue := this.Get(key)

        if (oldValue = value)
            return  ; No change

        this.state[key] := value

        ; Trigger watchers
        if (this.watchers.Has(key)) {
            for watcher in this.watchers[key] {
                SetTimer(() => watcher(value, oldValue), -1)
            }
        }

        ; Trigger computed properties
        this.UpdateComputed()
    }

    Watch(key, callback) {
        if (!this.watchers.Has(key))
            this.watchers[key] := []

        this.watchers[key].Push(callback)
    }

    Computed(key, getter) {
        ; Computed property that auto-updates
        this.Watch(key, (*) => {
            computed := getter()
            this.Set(key "_computed", computed)
        })

        ; Initial computation
        this.Set(key "_computed", getter())
    }

    UpdateComputed() {
        ; Would trigger computed property updates
    }
}

; Usage - Shopping Cart Example
cart := ReactiveState(Map("items", [], "total", 0))

; Watch total changes
cart.Watch("total", (newVal, oldVal) => {
    ToolTip("Cart total: $" newVal)
    SetTimer(() => ToolTip(), -2000)
})

; Watch item count
cart.Watch("items", (newVal, oldVal) => {
    OutputDebug("Cart now has " newVal.Length " items")
})

; Computed property
cart.Computed("itemCount", () => cart.Get("items").Length)

; Modify state
items := cart.Get("items")
items.Push({name: "Book", price: 10})
cart.Set("items", items)
cart.Set("total", 10)

MsgBox("Reactive state example - check tooltip and DebugView!")
```

---

## All 50 Examples Complete!

These advanced examples demonstrate:
- Hook systems and input manipulation
- Quasi-threading and timing control
- Debugger integration and introspection
- Overlay controls and advanced GUIs
- Memory and process manipulation
- WinAPI integration at low level
- Event systems and reactive patterns

Each example showcases techniques not commonly used in typical AutoHotkey scripts, drawing from the AutoHotkey v2 codebase internals and advanced programming patterns.
