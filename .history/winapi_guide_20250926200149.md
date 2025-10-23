# AutoHotkey Windows API (WinAPI) Comprehensive Developer Guide

## Overview

This guide provides comprehensive technical documentation of Windows API (WinAPI) function usage within the AutoHotkey v2 C++ interpreter. It serves as both a reference manual for developers maintaining or extending the AutoHotkey codebase and a practical implementation guide for building robust system-level automation applications in C++.

**Document Basis**: This guide is based on the detailed WinAPI inventory documented in `documentation.md` Section 4, which catalogs 50+ functions across 6 functional areas with complete parameter specifications, error handling patterns, and security considerations.

## Table of Contents

1. [Application Lifecycle & Initialization](<#1-application-lifecycle--initialization>)
2. [Process & Thread Management](<#2-process--thread-management>)
3. [Window Management & Messaging](<#3-window-management--messaging>)
4. [Low-Level Hooks & Input Interception](<#4-low-level-hooks--input-interception>)
5. [Keyboard/Mouse Input & State](<#5-keyboardmouse-input--state>)
6. [GUI & User Interface Controls](<#6-gui--user-interface-controls>)
7. [Security Considerations](<#7-security-considerations>)
8. [Performance & Best Practices](<#8-performance--best-practices>)
9. [Troubleshooting & Debugging](<#9-troubleshooting--debugging>)
10. [Appendices](<#10-appendices>)

---

## 1. Application Lifecycle & Initialization

### Key Functions Overview

| Function | Header | Purpose | AutoHotkey Context |
|----------|--------|---------|-------------------|
| `SetErrorMode` | winbase.h | Suppresses system error dialogs | Critical error prevention during automated operations |
| `FindResource` | winbase.h | Embedded resource location | Script loading from compiled executables |
| `MessageBox` | winuser.h | User notification dialogs | Single-instance prompts, critical errors |

### SetErrorMode - Error Dialog Suppression

**Parameters:**
- `SEM_FAILCRITICALERRORS`: Suppresses critical error dialogs and returns errors to caller

**Usage in AutoHotkey:**
```cpp
// Called during early initialization (_tWinMain)
SetErrorMode(SEM_FAILCRITICALERRORS);
```
**Security Implications:** Reduces interactive prompts but requires robust error handling.

**Failure Modes:** N/A (always succeeds as documented)

### FindResource - Embedded Resource Access

**Parameters:**
- `hModule`: Module handle (NULL for current executable)
- `lpName`: Resource identifier name
- `lpType`: Resource type (RT_RCDATA for scripts)

**Implementation Pattern:**
```cpp
HRSRC res = FindResource(NULL, SCRIPT_RESOURCE_NAME, RT_RCDATA);
if (!res) {
    DWORD error = GetLastError(); // Check ERROR_RESOURCE_DATA_NOT_FOUND
}
```

**Error Cases:**
- `ERROR_RESOURCE_DATA_NOT_FOUND`
- `ERROR_RESOURCE_TYPE_NOT_FOUND`

---

## 2. Process & Thread Management

### Threading Architecture Overview

AutoHotkey employs a sophisticated multi-threading model:
- **Main Thread**: Event loop processing, script execution
- **Hook Thread**: High-priority input interception (TIME_CRITICAL priority)
- **Quasi-Threads**: Cooperative scripting contexts (not OS threads)

### CreateThread - Hook Thread Initialization

**Critical Parameters:**
- `lpStartAddress`: `HookThreadProc` function
- `dwStackSize`: 8192 bytes (8KB stack allocation)
- `lpParameter`: NULL (no thread parameters)
- `dwCreationFlags`: 0 (start immediately)

**Thread Priority Setting:**
```cpp
SetThreadPriority(hThread, THREAD_PRIORITY_TIME_CRITICAL);
```
**Rationale:** Ensures minimal input latency for hotkey processing.

**Error Handling:**
```cpp
if (sThreadHandle) {
    DWORD error = GetLastError(); // Check ERROR_NOT_ENOUGH_MEMORY, ERROR_ACCESS_DENIED
}
```

---

## 3. Window Management & Messaging

### Core Functions Matrix

| Function | Primary Purpose | Key Parameters | Common Errors |
|----------|----------------|----------------|---------------|
| `FindWindow(Ex)` | Window discovery | Class name, window title | Window not found |
| `GetWindowText` | Text retrieval | Buffer, max length | Access denied, invalid handle |
| `SendMessage` | Synchronous messaging | Window handle, message ID, params | Message not processed |
| `PostMessage` | Asynchronous messaging | Window handle, message ID, params | Queue full, invalid handle |

### Window State Management Implementation

**Activation Sequence:**
```cpp
if (HWND hwnd = FindWindow(lpClassName, lpWindowName)) {
    SetForegroundWindow(hwnd);  // Bring to front
    SetFocus(hwnd);            // Set input focus
    SetActiveWindow(hwnd);     // Alternative activation
}
```

**Message Processing Loop:**
```cpp
// Main event loop (MsgSleep implementation)
MSG msg;
while (GetMessage(&msg, NULL, 0, MSG_FILTER_MAX)) {
    if (IsDialogMessage(g_hWnd, &msg)) continue;
    TranslateMessage(&msg);
    DispatchMessage(&msg);
}
```

**GUI Control Special Handling:**
```cpp
// Dialog message processing
if (IsDialogMessage(hDialog, &msg)) {
    // Handles tab order and accelerator keys automatically
    continue;
}
```

---

## 4. Low-Level Hooks & Input Interception

### Hook Installation and Management

**Global Hook Setup:**
```cpp
// Keyboard hook installation
g_KeybdHook = SetWindowsHookEx(WH_KEYBOARD_LL,
                              LowLevelKeybdProc,
                              hInstance,
                              0); // dwThreadId = 0 for global
```

**Mouse Hook Setup:**
```cpp
g_MouseHook = SetWindowsHookEx(WH_MOUSE_LL,
                             LowLevelMouseProc,
                             hInstance,
                             0);
```

**Hook Chain Processing:**
```cpp
// Standard hook continuation
return CallNextHookEx(g_KeybdHook, nCode, wParam, lParam);
```

### Hook Procedure Implementation

**Keyboard Hook Framework:**
```cpp
LRESULT CALLBACK LowLevelKeybdProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION) {
        KBDLLHOOKSTRUCT* pKB = (KBDLLHOOKSTRUCT*)lParam;

        // Process key event...
        return CallNextHookEx(g_KeybdHook, nCode, wParam, lParam);
    }
    return CallNextHookEx(g_KeybdHook, nCode, wParam, lParam);
}
```

**Security and Privilege Requirements:**
- **Administrator Privileges Required** for global hooks on modern Windows versions
- **UIPI Bypass** consideration for elevated process communication

### Hook Cleanup and Error Handling

**Hook Removal:**
```cpp
if (g_KeybdHook) {
    UnhookWindowsHookEx(g_KeybdHook);
    g_KeybdHook = NULL;
}
```

**Failure Cases:**
- `NULL` return from `SetWindowsHookEx`
- `GetLastError()` codes: `ERROR_NOT_ENOUGH_MEMORY`, `ERROR_ACCESS_DENIED`

---

## 5. Keyboard/Mouse Input & State

### Input Synthesis Functions

**SendInput - Modern Input Injection:**
```cpp
INPUT input[2] = {0};
input[0].type = INPUT_KEYBOARD;
input[0].ki.wVk = keyCode;
input[0].ki.dwFlags = 0; // Key down

input[1].type = INPUT_KEYBOARD;
input[1].ki.wVk = keyCode;
input[1].ki.dwFlags = KEYEVENTF_KEYUP; // Key up

UINT result = SendInput(2, input, sizeof(INPUT));
if (result != 2) {
    DWORD error = GetLastError();
}
```

**Legacy Methods (Backward Compatibility):**
```cpp
// Older API (consider SendInput instead)
keybd_event(vkCode, scanCode, 0, 0);          // Key down
keybd_event(vkCode, scanCode, KEYEVENTF_KEYUP, 0); // Key up
```

### Input Level Management (SendLevel)

**Purpose:** Prevents infinite input processing loops in automation scenarios.

**Implementation:**
```cpp
// SendLevel prevents recursive input processing
#define INPUT_LEVEL_DEFAULT 0
#define INPUT_LEVEL_SUPERIOR (INPUT_LEVEL_MAX + 3)

// Check against current input processing level
if (input_level >= g->InputLevel) {
    // Process synthetic input
} else {
    // Suppress to prevent loops
    return 1; // Block event
}
```

### Character Translation and Keyboard Layouts

**ToUnicodeEx Usage:**
```cpp
WCHAR ch[4];
int result = ToUnicodeEx(vkCode, scanCode, key_state, ch,
                        ARRAYSIZE(ch), 0,
                        GetKeyboardLayout(0));
if (result == -1) {
    // Dead key processed
}
```

**Unicode vs ANSI Considerations:**
- Prefer Unicode APIs (`W` variants) for internationalization
- Handle codepage conversions with `MultiByteToWideChar`

---

## 6. GUI & User Interface Controls

### Window Creation and Management

**CreateWindowEx - Control Creation:**
```cpp
HWND hwndControl = CreateWindowEx(
    WS_EX_CLIENTEDGE,        // Extended styles
    WC_EDIT,                 // Class name
    L"",                     // Window text
    WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL, // Styles
    x, y, width, height,     // Position/dimensions
    hwndParent,             // Parent window
    (HMENU)controlID,        // Menu/control ID
    g_hInstance,            // Instance handle
    NULL                    // Creation data
);
```

### Menu System Integration

**Menu Info Management:**
```cpp
MENUINFO mi = {0};
mi.cbSize = sizeof(MENUINFO);
mi.fMask = MIM_STYLE;
mi.dwStyle = MNS_MODELESS; // Modeless menu behavior

SetMenuInfo(hMenu, &mi);
```

### Drag-and-Drop Support

**File Drop Handling:**
```cpp
UINT count = DragQueryFile(hDrop, 0xFFFFFFFF, NULL, 0);
for (UINT i = 0; i < count; i++) {
    TCHAR filename[MAX_PATH];
    DragQueryFile(hDrop, i, filename, MAX_PATH);
    // Process dropped file
}
DragFinish(hDrop);
```

---

## 7. Security Considerations

### Privilege Escalation Risks

**Critical Security Functions:**
- `SendInput`: Can inject arbitrary input (equivalent to keyboard usage)
- `SetWindowsHookEx`: Global hook installation requires admin privileges
- `SendMessage/PostMessage`: Potential for shatter attacks with malicious parameters

### Integrity Level Isolation (UIPI)

**UIPI Constraints:**
```cpp
// Input injection blocked to higher integrity processes
SendInput(...) // Fails silently if target has higher IL
```

**Workarounds:** Signed and cataloged applications can bypass some restrictions.

### Safe Coding Patterns

**Handle Validation:**
```cpp
BOOL IsValidWindow(HWND hwnd) {
    return IsWindow(hwnd) && GetWindowThreadProcessId(hwnd, NULL);
}
```

**Privilege-Aware Code:**
```cpp
// Check elevation status before privileged operations
TOKEN_ELEVATION elevation;
GetTokenInformation(hToken, TokenElevation, &elevation, sizeof(elevation), &size);
```

---

## 8. Performance & Best Practices

### Critical Path Optimization

**Hook Thread Performance:**
- Hook procedures execute for every system input event
- Keep processing minimal (μs range) to avoid input latency
- Avoid heap allocations in hook chains

**Memory Management:**
- Pre-allocate frequently used buffers
- Use custom allocators for performance-critical paths
- Monitor handle lifetime to prevent leaks

### Threading Safety

**Shared State Access:**
```cpp
// Volatile modifiers for compiler barriers
volatile LONG g_nThreads;
// Use Interlocked* functions for atomic operations
InterlockedIncrement(&g_nThreads);
```

**Message-Based Synchronization:**
```cpp
// PostThreadMessage for thread-safe communication
PostThreadMessage(hookThreadId, AHK_CHANGE_HOOK_STATE, wParam, lParam);
```

---

## 9. Troubleshooting & Debugging

### Key History and Diagnostic Tools

**Key History Buffer:**
```cpp
// Enable input history for debugging
SetKeyHistoryMax(500); // Store 500 recent events

// Retrieve diagnostic output
GetHookStatus(historyBuffer, bufferSize);
```

**Format:** VK SC Type Up/Dn Elapsed Key Window

### Debugging Hook Issues

**Hook Installation Failures:**
- Verify administrator privileges
- Check for conflicting hooks (same user session)
- Review GetLastError() codes

**Input Blocking Problems:**
- Examine SendLevel settings
- Check hotkey criteria firing
- Monitor key history for unexpected suppression

### Common Error Scenarios

**ERROR_ACCESS_DENIED:**
- Privilege elevation required
- Target window integrity level mismatch

**ERROR_INVALID_HANDLE:**
- Resource lifetime issues
- Proper cleanup verification needed

### Performance Profiling

**Hook Latency Measurement:**
- Track hook procedure execution time
- Monitor input event queue depth
- Identify processing bottlenecks

---

## 10. Appendices

### Function Reference Index

#### Window Management
- `FindWindowEx`, `GetWindowText`, `SetWindowText`
- `SetWindowPos`, `MoveWindow`, `ShowWindow`
- `BringWindowToTop`, `SetForegroundWindow`

#### Input Processing
- `SetWindowsHookEx`, `UnhookWindowsHookEx`
- `SendInput`, `keybd_event`, `mouse_event`
- `ToUnicodeEx`, `GetKeyboardState`

#### File Operations
- `CreateFile`, `ReadFile`, `WriteFile`
- `MultiByteToWideChar`, `WideCharToMultiByte`

#### Process Management
- `CreateThread`, `SetThreadPriority`
- `PostThreadMessage`, `CreateMutex`

### Error Code Reference

**Common WinAPI Error Codes:**
- `ERROR_NOT_ENOUGH_MEMORY` (0x8): Memory allocation failure
- `ERROR_ACCESS_DENIED` (0x5): Insufficient privileges
- `ERROR_INVALID_HANDLE` (0x6): Invalid resource handle
- `ERROR_INVALID_PARAMETER` (0x57): Invalid function parameter

### Compatibility Matrix

**Windows Version Support:**
- **Vista+**: Integrity levels, UAC consideration
- **Win7+**: Enhanced touch, UI Automation
- **Win8+**: Modern app isolation
- **Win10+**: App container restrictions

### Implementation Checklist

**New WinAPI Integration:**
- [ ] Add error handling pattern
- [ ] Include security consideration documentation
- [ ] Add performance impact assessment
- [ ] Update privilege requirements documentation
- [ ] Add threading safety analysis
- [ ] Update cleanup/shutdown sequences

## References

- **[AutoHotkey Technical Documentation](documentation.md)** - Original specification and WinAPI inventory
- **[MSDN Windows API Reference](https://docs.microsoft.com/en-us/windows/win32/api/)** - Official function documentation
- **[Windows Hooks Overview](https://docs.microsoft.com/en-us/windows/win32/winmsg/hooks)** - Hook system architecture
- **[Input Handling Architecture](https://docs.microsoft.com/en-us/windows-hardware/drivers/hid/)** - Input system design
- **[Process Security Architecture](https://docs.microsoft.com/en-us/windows/win32/procthread/process-security-and-access-rights)** - Security model reference

---

**Document Version:** 1.0
**Based on:** AutoHotkey C++ interpreter codebase analysis
**Last Reviewed:** Documentation review of WinAPI Sections 1-6
