# How AutoHotkey v2 Works - C++ Implementation Deep Dive

**Technical Analysis of the AutoHotkey v2 C++ Interpreter**

This document explains exactly how AutoHotkey v2 works under the hood, with real code examples from the C++ implementation.

---

## Table of Contents

1. [Startup Sequence](#startup-sequence)
2. [Script Parsing and Loading](#script-parsing-and-loading)
3. [The Hook System](#the-hook-system)
4. [Quasi-Threading Model](#quasi-threading-model)
5. [Event Loop (MsgSleep)](#event-loop-msgsleep)
6. [Hotkey Processing](#hotkey-processing)
7. [Command Execution](#command-execution)
8. [Memory Management](#memory-management)
9. [Complete Example Flow](#complete-example-flow)

---

## 1. Startup Sequence

### Entry Point: `_tWinMain`

**File:** `source/AutoHotkey.cpp:66-92`

```cpp
int WINAPI _tWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
                     LPTSTR lpCmdLine, int nCmdShow)
{
    // Step 1: Store application instance handle
    g_hInstance = hInstance;

    // Step 2: Early initialization
    EarlyAppInit();

    // Step 3: Parse command-line arguments
    LPTSTR script_filespec;
    if (!ParseCmdLineArgs(script_filespec))
        return CRITICAL_ERROR;

    // Step 4: Load and parse the script
    UINT load_result = g_script.LoadFromFile(script_filespec);
    if (load_result == LOADING_FAILED)
        return CRITICAL_ERROR;
    if (!load_result)
        return 0;  // No script loaded (e.g., /validate mode)

    // Step 5: Check for prior instance (#SingleInstance)
    switch (CheckPriorInstance())
    {
    case EARLY_EXIT: return 0;
    case FAIL: return CRITICAL_ERROR;
    }

    // Step 6: Initialize for execution
    if (!InitForExecution())
        return CRITICAL_ERROR;

    // Step 7: Execute the script
    return MainExecuteScript();
}
```

### Step-by-Step Breakdown

#### Step 1: Early Initialization

**File:** `source/AutoHotkey.cpp:38-63`

```cpp
void EarlyAppInit()
{
    // Prevent system error dialogs for critical errors
    SetErrorMode(SEM_FAILCRITICALERRORS);

    // Initialize working directory
    UpdateWorkingDir();
    g_WorkingDirOrig = SimpleHeap::Alloc(g_WorkingDir.GetString());

    // Initialize global state structure
    global_init(*g);

    // Initialize the object model (for AHK v2 objects)
    Object::CreateRootPrototypes();
}
```

**What happens:**
1. **SetErrorMode** - Prevents Windows from showing error dialogs for missing drives, etc.
2. **UpdateWorkingDir** - Sets `g_WorkingDir` to current directory
3. **global_init** - Initializes the `global_struct` which holds all script state
4. **CreateRootPrototypes** - Sets up base objects for AHK v2 object system

#### Step 2: Command-Line Parsing

**File:** `source/AutoHotkey.cpp:95-202`

```cpp
ResultType ParseCmdLineArgs(LPTSTR &script_filespec)
{
    script_filespec = NULL;

    // Check if this is a compiled script
    if (FindResource(NULL, SCRIPT_RESOURCE_NAME, RT_RCDATA))
        script_filespec = SCRIPT_RESOURCE_SPEC;

    // Parse command-line arguments
    for (i = 1; i < __argc; ++i)
    {
        LPTSTR param = __targv[i];

        if (!_tcsicmp(param, _T("/restart")))
            g_script.mIsRestart = true;
        else if (!_tcsicmp(param, _T("/force")))
            g_ForceLaunch = true;
        else if (!_tcsnicmp(param, _T("/Debug"), 6))
        {
            // Parse /Debug=host:port
            // Store in g_DebuggerHost and g_DebuggerPort
        }
        else
        {
            // First non-switch argument is the script file
            script_filespec = param;
            ++i;
            break;
        }
    }

    // Remaining args go to the script (A_Args)
    auto args = Array::FromArgV(__targv + i, __argc - i);
    return g_script.Init(script_filespec, args);
}
```

**Supported flags:**
- `/Debug[=host:port]` - Enable debugger
- `/restart` - Script is restarting
- `/force` - Ignore #SingleInstance
- `/ErrorStdOut` - Send errors to stderr
- `/CP1252` - Set script file codepage

---

## 2. Script Parsing and Loading

### Loading the Script File

**File:** `source/script.cpp` (simplified)

```cpp
UINT Script::LoadFromFile(LPTSTR aFileSpec)
{
    // Step 1: Open the script file
    TextFile file;
    if (!file.Open(aFileSpec, DEFAULT_READ_FLAGS))
    {
        // Show error: "Script file not found"
        return LOADING_FAILED;
    }

    // Step 2: Read lines and parse
    TCHAR line_buf[LINE_SIZE];
    while (file.ReadLine(line_buf, LINE_SIZE))
    {
        // Parse the line
        if (!ParseAndAddLine(line_buf))
            return LOADING_FAILED;
    }

    // Step 3: Post-processing
    // - Resolve labels and function calls
    // - Validate hotkey definitions
    // - Build hotkey/hotstring lookup tables
    if (!PreparseBlocks())
        return LOADING_FAILED;

    return LOAD_OK;
}
```

### Parsing a Single Line

**File:** `source/script.cpp`

```cpp
ResultType Script::ParseAndAddLine(LPTSTR aLineText)
{
    // Step 1: Strip comments and whitespace
    LPTSTR line_start = omit_leading_whitespace(aLineText);
    if (!*line_start || *line_start == g_CommentChar)
        return OK;  // Blank or comment line

    // Step 2: Check for directives (#Include, #Requires, etc.)
    if (*line_start == '#')
        return ParseDirective(line_start + 1);

    // Step 3: Check for hotkey/hotstring definition
    if (IsHotkeyOrHotstring(line_start))
        return ParseHotkey(line_start);

    // Step 4: Check for label definition (MyLabel:)
    if (LPTSTR colon = _tcschr(line_start, ':'))
    {
        if (colon[1] != ':')  // Not :: (hotstring)
            return ParseLabel(line_start, colon);
    }

    // Step 5: Parse as regular statement/expression
    return ParseStatement(line_start);
}
```

### Internal Representation

**Data Structure:**

```cpp
// Each line becomes a Line object
class Line
{
public:
    ActionTypeType mActionType;  // ACT_EXPRESSION, ACT_IF, ACT_LOOP, etc.
    LPTSTR mName;                // For labels, function names
    Line *mNextLine;             // Linked list of lines
    Line *mRelatedLine;          // For if/else, loop/break, etc.
    ArgStruct *mArg;             // Array of arguments
    int mArgc;                   // Argument count
    FileIndexType mFileIndex;    // Which file this line came from
    LineNumberType mLineNumber;  // Line number in file

#ifdef CONFIG_DEBUGGER
    Breakpoint *mBreakpoint;     // Debugger breakpoint
#endif
};
```

---

## 3. The Hook System

### Hook Thread Architecture

AutoHotkey uses a **dedicated high-priority thread** for input interception.

**Why a separate thread?**
- The main thread can be blocked by scripts (MsgBox, Sleep, etc.)
- Input events need immediate processing (< 1ms latency)
- Hook procedures must return quickly or Windows will bypass them

### Hook Thread Startup

**File:** `source/hook.cpp`

```cpp
DWORD WINAPI HookThreadProc(LPVOID aParam)
{
    // Set high priority for minimal input lag
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);

    // Install low-level keyboard hook
    g_KeybdHook = SetWindowsHookEx(
        WH_KEYBOARD_LL,           // Low-level keyboard hook
        LowLevelKeybdProc,        // Callback function
        g_hInstance,              // Module handle
        0                         // 0 = global (all threads)
    );

    // Install low-level mouse hook
    g_MouseHook = SetWindowsHookEx(
        WH_MOUSE_LL,              // Low-level mouse hook
        LowLevelMouseProc,        // Callback function
        g_hInstance,
        0
    );

    // Message loop for hook thread
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0))
    {
        // Process control messages (e.g., change hook state)
        if (msg.message == AHK_CHANGE_HOOK_STATE)
        {
            // Update hooks based on script changes
        }

        DispatchMessage(&msg);
    }

    // Cleanup on exit
    UnhookWindowsHookEx(g_KeybdHook);
    UnhookWindowsHookEx(g_MouseHook);
    return 0;
}
```

### Keyboard Hook Callback

**File:** `source/hook.cpp:171-600` (simplified)

```cpp
LRESULT CALLBACK LowLevelKeybdProc(int aCode, WPARAM wParam, LPARAM lParam)
{
    // Must call next hook if aCode < 0
    if (aCode != HC_ACTION)
        return CallNextHookEx(g_KeybdHook, aCode, wParam, lParam);

    // Get event details
    KBDLLHOOKSTRUCT &event = *(PKBDLLHOOKSTRUCT)lParam;

    bool key_up = (wParam == WM_KEYUP || wParam == WM_SYSKEYUP);
    vk_type vk = (vk_type)event.vkCode;
    sc_type sc = (sc_type)event.scanCode;

    // Ignore events we generated ourselves
    if (event.dwExtraInfo == KEY_IGNORE)
        return CallNextHookEx(g_KeybdHook, aCode, wParam, lParam);

    // Update modifier key states
    UpdateModifierLRState(vk, sc, key_up, event.dwExtraInfo);

    // Check for hotkey match
    HotkeyIDType hotkey_id = FindHotkeyMatch(vk, sc,
                                             g_modifiersLR_logical,
                                             key_up);

    if (hotkey_id != HOTKEY_ID_INVALID)
    {
        Hotkey *hk = Hotkey::FindHotkeyByID(hotkey_id);

        // Check if hotkey should fire (criteria, input level, etc.)
        if (hk && hk->CriterionAllowsFiring(NULL, /*aHotkeyDown*/ true))
        {
            // Post message to main thread to execute hotkey
            PostMessage(g_hWnd, AHK_HOOK_HOTKEY,
                       (WPARAM)hotkey_id,
                       (LPARAM)g_modifiersLR_logical);

            // Should we suppress this key?
            if (!hk->mNoSuppress)
                return TRUE;  // Suppress (don't pass to OS)
        }
    }

    // Check for hotstring match
    if (!key_up && IsCharKey(vk))
    {
        // Add character to hotstring buffer
        CollectHotstring(vk, sc, event.dwExtraInfo);
    }

    // Pass event to next hook in chain
    return CallNextHookEx(g_KeybdHook, aCode, wParam, lParam);
}
```

### Hotkey Lookup Optimization

**The key insight:** Instead of searching through all hotkeys, use pre-computed lookup tables.

**Data Structure:**

```cpp
// Two-dimensional arrays: [modifiers][key]
static HotkeyIDType *kvkm = NULL;  // Virtual key lookup
static HotkeyIDType *kscm = NULL;  // Scan code lookup

// Access macros
#define Kvkm(modifiers, vk) kvkm[(modifiers)*(VK_ARRAY_COUNT) + (vk)]
#define Kscm(modifiers, sc) kscm[(modifiers)*(SC_ARRAY_COUNT) + (sc)]

// Example: Ctrl+J is stored at:
// Kvkm[MOD_LCONTROL, 'J'] = hotkey_id
```

**Lookup is O(1):**

```cpp
HotkeyIDType FindHotkeyMatch(vk_type aVK, sc_type aSC,
                             modLR_type aModifiers, bool aKeyUp)
{
    // Convert left/right modifiers to neutral
    mod_type neutral_mods = ConvertModifiersLR(aModifiers);

    // Check virtual key table
    HotkeyIDType id = Kvkm(neutral_mods, aVK);
    if (id != HOTKEY_ID_INVALID)
        return id;

    // Check scan code table
    id = Kscm(neutral_mods, aSC);
    if (id != HOTKEY_ID_INVALID)
        return id;

    // Check for custom combos (a & b::)
    if (pPrefixKey)  // A prefix key is currently down
    {
        // Search for suffix hotkeys using this prefix
        for (HotkeyIDType *id_ptr = pPrefixKey->first_hotkey;
             id_ptr;
             id_ptr = id_ptr->next)
        {
            if (id_ptr->vk == aVK || id_ptr->sc == aSC)
                return id_ptr->id;
        }
    }

    return HOTKEY_ID_INVALID;
}
```

---

## 4. Quasi-Threading Model

### What is Quasi-Threading?

AutoHotkey doesn't use real OS threads for script execution. Instead, it uses **cooperative multitasking** with a stack of execution contexts.

**Why?**
- True threads would require complex synchronization for GUI and variables
- Hotkeys need to interrupt running scripts
- Timers need to fire while scripts are running
- But we need controlled, predictable execution

### The Global State Stack

**File:** `source/globaldata.h:166-167`

```cpp
extern global_struct *g;        // Current execution context
extern global_struct *g_array;  // Stack of contexts

#define g_default g_array[0]    // Default/base context
```

**Structure:**

```cpp
struct global_struct
{
    // Current script state
    Line *mCurrLine;              // Currently executing line
    ResultType *mLastScriptRet;   // Return value from last call
    HWND hWndLastUsed;            // Last window used

    // Settings (can differ per thread)
    int KeyDelay;                 // SetKeyDelay value
    int WinDelay;                 // SetWinDelay value
    int ControlDelay;             // SetControlDelay value
    SendModes SendMode;           // SendMode value
    CoordModeType CoordMode;      // CoordMode value

    // Thread state
    bool AllowThreadToBeInterrupted;
    DWORD ThreadStartTime;
    DWORD UninterruptibleDuration;
    int ThreadPriority;

    // Error handling
    ExprTokenType *ThrownToken;   // Exception being thrown
    Line *mExcptLine;             // Line that threw exception

    // ... many more fields (100+ total)
};

// The stack
#define MAX_THREADS_LIMIT 255
global_struct g_array[MAX_THREADS_LIMIT + TOTAL_ADDITIONAL_THREADS];
```

### Creating a New Thread

**File:** `source/application.cpp`

```cpp
void InitNewThread(int aPriority, bool aSkipUninterruptible,
                   bool aIncrementThreadCount, bool aIsCritical)
{
    // Check thread limit
    if (g_nThreads >= g_MaxThreadsTotal)
    {
        // Too many threads, buffer or reject
        return;
    }

    // Push new context onto stack
    ++g;  // Move to next slot in g_array

    // Copy default settings from g_default
    memcpy(g, &g_default, sizeof(global_struct));

    // Set thread-specific state
    g->ThreadStartTime = GetTickCount();
    g->ThreadPriority = aPriority;
    g->AllowThreadToBeInterrupted = !aIsCritical;

    if (!aSkipUninterruptible)
    {
        // Set uninterruptible period
        g->UninterruptibleDuration = g_DefaultUninterruptibleTime;
    }

    // Increment global thread counter
    if (aIncrementThreadCount)
    {
        ++g_nThreads;
        UpdateTrayIcon();  // Update to show script is running
    }

#ifdef CONFIG_DEBUGGER
    // Notify debugger of new thread
    DEBUGGER_STACK_PUSH(GetCurrentThreadDesc());
#endif
}
```

### Resuming Previous Thread

**File:** `source/application.cpp`

```cpp
void ResumeUnderlyingThread()
{
    // Decrement thread counter
    if (g->mThisThreadIsTopLevel)
    {
        --g_nThreads;
        if (g_nThreads == 0)
            UpdateTrayIcon();  // Show script is idle
    }

#ifdef CONFIG_DEBUGGER
    DEBUGGER_STACK_POP();
#endif

    // Pop context from stack
    --g;  // Move back to previous slot in g_array

    // Previous thread is now active
    // Its state (variables, settings, current line) is restored
}
```

### Example Thread Stack

```
g_array[0] (g_default)  ← Base settings
g_array[1]              ← Auto-execute section
g_array[2]              ← Hotkey ^j:: triggered
g_array[3]              ← Function MyFunc() called
g_array[4]              ← Timer fired     ← g points here (current)
```

---

## 5. Event Loop (MsgSleep)

### The Heart of AutoHotkey

**File:** `source/application.cpp:100-500` (simplified)

```cpp
bool MsgSleep(int aSleepDuration, MessageMode aMode)
{
    // This function replaces ALL calls to Sleep() in the code
    // It processes Windows messages while "sleeping"

    DWORD start_time = GetTickCount();
    DWORD sleep_until = start_time + aSleepDuration;

    // Set main timer to wake us up
    SET_MAIN_TIMER;

    MSG msg;
    for (;;)  // Infinite loop until sleep duration expires
    {
        // Check if sleep duration has elapsed
        if (aSleepDuration != INTERVAL_UNSPECIFIED)
        {
            if (GetTickCount() >= sleep_until)
                break;  // Done sleeping
        }

        // Get message from queue
        // Use PeekMessage for non-blocking, GetMessage for blocking
        bool got_message;
        if (aMode == RETURN_AFTER_MESSAGES)
        {
            got_message = PeekMessage(&msg, NULL, 0, MSG_FILTER_MAX, PM_REMOVE);
            if (!got_message)
                break;  // No messages, return immediately
        }
        else  // WAIT_FOR_MESSAGES
        {
            got_message = GetMessage(&msg, NULL, 0, MSG_FILTER_MAX);
        }

        if (!got_message || msg.message == WM_QUIT)
            break;

        // Handle AutoHotkey-specific messages
        switch (msg.message)
        {
        case AHK_HOOK_HOTKEY:
            // Hotkey fired from hook thread
            {
                HotkeyIDType hotkey_id = (HotkeyIDType)msg.wParam;
                Hotkey *hk = Hotkey::FindHotkeyByID(hotkey_id);

                if (hk)
                {
                    // Create new thread and execute hotkey
                    InitNewThread(hk->mPriority, false, true);
                    hk->PerformInNewThreadMadeByCaller();
                    ResumeUnderlyingThread();
                }
            }
            break;

        case AHK_HOTSTRING:
            // Hotstring matched
            {
                HotstringIDType hs_id = (HotstringIDType)msg.wParam;
                Hotstring *hs = Hotstring::FindByID(hs_id);

                if (hs)
                {
                    // Backspace the typed abbreviation
                    hs->DoReplace();

                    // Execute hotstring callback if any
                    if (hs->mCallback)
                    {
                        InitNewThread(hs->mPriority, false, true);
                        hs->mCallback->Call();
                        ResumeUnderlyingThread();
                    }
                }
            }
            break;

        case AHK_GUI_ACTION:
            // GUI event (button click, etc.)
            {
                WORD control_index = HIWORD(msg.wParam);
                WORD gui_event = LOWORD(msg.wParam);

                GuiType *gui = GuiType::FindGui(msg.hwnd);
                if (gui)
                {
                    gui->HandleEvent(control_index, gui_event, msg.lParam);
                }
            }
            break;

        case WM_TIMER:
            // Check script timers
            if (g_script.mTimerEnabledCount)
                CheckScriptTimers();
            break;

        default:
            // Standard message processing
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            break;
        }

        // Check if we should poll joysticks
        if (Hotkey::sJoyHotkeyCount)
            PollJoysticks();
    }

    KILL_MAIN_TIMER;
    return true;
}
```

### Message Filtering

**Key mechanism:** `MSG_FILTER_MAX` controls which messages are processed.

```cpp
// From source/application.h:52
#define MSG_FILTER_MAX (IsInterruptible() ? 0 : WM_HOTKEY - 1)

bool IsInterruptible()
{
    // Can this thread be interrupted by hotkeys?
    if (!g_AllowInterruption)
        return FALSE;

    if (g_MenuIsVisible)
        return FALSE;  // Don't interrupt during menu display

    if (!g->AllowThreadToBeInterrupted)
        return FALSE;  // Critical section

    // Check if uninterruptible duration has expired
    if (g->UninterruptibleDuration != -1)
    {
        DWORD elapsed = GetTickCount() - g->ThreadStartTime;
        if (elapsed < g->UninterruptibleDuration)
            return FALSE;
    }

    return TRUE;
}
```

**When interruptible:**
- `MSG_FILTER_MAX = 0` → Process all messages (including WM_HOTKEY)

**When not interruptible:**
- `MSG_FILTER_MAX = WM_HOTKEY - 1` → Skip WM_HOTKEY and higher
- Hotkey messages are buffered, not processed

---

## 6. Hotkey Processing

### From Key Press to Script Execution

**Complete flow:**

```
1. User presses Ctrl+J
   ↓
2. Windows sends key event to hook
   ↓
3. LowLevelKeybdProc() called
   ↓
4. Update g_modifiersLR_logical (Ctrl is down)
   ↓
5. FindHotkeyMatch() → Returns hotkey ID
   ↓
6. PostMessage(AHK_HOOK_HOTKEY, hotkey_id)
   ↓
7. Return TRUE to suppress key (or FALSE to allow)
   ↓
8. Main thread's MsgSleep() receives message
   ↓
9. InitNewThread() creates new context
   ↓
10. Hotkey::PerformInNewThreadMadeByCaller()
    ↓
11. Execute hotkey's script lines
    ↓
12. ResumeUnderlyingThread()
```

### Hotkey Execution

**File:** `source/hotkey.cpp`

```cpp
void Hotkey::PerformInNewThreadMadeByCaller()
{
    // Find the variant that should fire
    HotkeyVariant *variant = FindVariant();
    if (!variant || !variant->mCallback)
        return;

    // Store hotkey info for A_ThisHotkey, A_PriorHotkey
    g->mThisHotkey = this;

    // Call the hotkey function/label
    variant->mCallback->Call();

    // If callback returns, execution continues here
}
```

### Hotstring Processing

**File:** `source/hook.cpp`

```cpp
void CollectHotstring(vk_type aVK, sc_type aSC, ULONG_PTR aExtraInfo)
{
    // Translate key to character
    TCHAR ch[2];
    if (!VK_TO_CHAR(aVK, aSC, ch))
        return;  // Not a character key

    // Add to hotstring buffer
    if (g_HSBufLength < HS_BUF_SIZE - 1)
    {
        g_HSBuf[g_HSBufLength++] = ch[0];
        g_HSBuf[g_HSBufLength] = '\0';
    }
    else
    {
        // Buffer full, shift left
        memmove(g_HSBuf, g_HSBuf + 1, HS_BUF_SIZE - 1);
        g_HSBuf[HS_BUF_SIZE - 2] = ch[0];
    }

    // Check all hotstrings for match
    for (Hotstring *hs = g_script.mFirstHotstring; hs; hs = hs->mNextHotstring)
    {
        if (!hs->mEnabled)
            continue;

        // Check if buffer ends with hotstring
        int buf_len = g_HSBufLength;
        int hs_len = hs->mStringLength;

        if (buf_len < hs_len)
            continue;

        LPTSTR buf_end = g_HSBuf + buf_len - hs_len;

        bool match;
        if (hs->mCaseSensitive)
            match = !_tcscmp(buf_end, hs->mString);
        else
            match = !_tcsicmp(buf_end, hs->mString);

        if (match)
        {
            // Found a match!
            PostMessage(g_hWnd, AHK_HOTSTRING, (WPARAM)hs->mID, 0);

            // Reset buffer if configured
            if (hs->mDoReset)
                g_HSBufLength = 0;

            break;
        }
    }
}
```

---

## 7. Command Execution

### Executing a Script Line

**File:** `source/script.cpp:10000-10200` (simplified)

```cpp
ResultType Line::ExecUntil(ExecUntilMode aMode, ResultType *aResultToken)
{
    Line *line = this;  // Start at current line

    for (; line; line = line->mNextLine)
    {
#ifdef CONFIG_DEBUGGER
        // Debugger hook before each line
        if (g_Debugger.IsConnected())
            g_Debugger.PreExecLine(line);
#endif

        ResultType result;

        switch (line->mActionType)
        {
        case ACT_EXPRESSION:
            // Evaluate expression
            result = line->EvaluateExpression(aResultToken);
            break;

        case ACT_ASSIGN:
            // Variable assignment
            result = line->PerformAssignment();
            break;

        case ACT_IF:
            // If statement
            result = line->EvaluateCondition();
            if (result == CONDITION_TRUE)
                line->mRelatedLine->ExecUntil(UNTIL_BLOCK_END);
            else if (line->mRelatedLine2)  // else clause
                line->mRelatedLine2->ExecUntil(UNTIL_BLOCK_END);
            break;

        case ACT_LOOP:
            // Loop statement
            result = line->PerformLoop();
            break;

        case ACT_RETURN:
            // Return from function
            if (line->mArg[0])
                line->EvaluateExpression(aResultToken);
            return EARLY_RETURN;

        case ACT_BREAK:
            return LOOP_BREAK;

        case ACT_CONTINUE:
            return LOOP_CONTINUE;

        // ... many more action types
        }

        if (result == FAIL || result == EARLY_EXIT)
            return result;
    }

    return OK;
}
```

### Calling a Built-In Function

**File:** `source/script_expression.cpp`

```cpp
ResultType CallBuiltInFunc(NativeFunc *aFunc, ExprTokenType &aResultToken,
                           ExprTokenType **aParam, int aParamCount)
{
    // Examples of built-in functions:
    // - MsgBox, Send, Sleep, WinActivate, etc.

    // Call the C++ implementation
    ResultType result = aFunc->mImpl(aResultToken, aParam, aParamCount);

    return result;
}

// Example: MsgBox implementation
ResultType BIF_MsgBox(ResultToken &aResultToken, ExprTokenType **aParam, int aParamCount)
{
    // Parse parameters
    LPCTSTR text = TokenToString(*aParam[0]);
    LPCTSTR title = aParamCount > 1 ? TokenToString(*aParam[1]) : _T("AutoHotkey");
    UINT options = aParamCount > 2 ? (UINT)TokenToInt64(*aParam[2]) : 0;

    // Call Windows API
    int result = MessageBox(g_hWnd, text, title, options);

    // Return result
    aResultToken.SetValue(result);
    return OK;
}
```

### Sending Keystrokes

**File:** `source/keyboard_mouse.cpp`

```cpp
ResultType BIF_Send(ResultToken &aResultToken, ExprTokenType **aParam, int aParamCount)
{
    LPCTSTR keys = TokenToString(*aParam[0]);

    // Parse the keystroke string
    for (LPCTSTR cp = keys; *cp; )
    {
        if (*cp == '{')
        {
            // Special key like {Enter}, {Tab}, etc.
            cp = ParseSpecialKey(cp, &event);
        }
        else
        {
            // Regular character
            event.vk = VkKeyScan(*cp);
            event.sc = MapVirtualKey(event.vk, MAPVK_VK_TO_VSC);
        }

        // Send the key
        SendKeyEvent(event.vk, event.sc, event.flags);

        // Apply key delay
        if (g->KeyDelay > -1)
            MsgSleep(g->KeyDelay);
    }

    return OK;
}

void SendKeyEvent(vk_type aVK, sc_type aSC, DWORD aFlags)
{
    INPUT input = {0};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = aVK;
    input.ki.wScan = aSC;
    input.ki.dwFlags = aFlags;
    input.ki.dwExtraInfo = KEY_IGNORE;  // Mark as AHK-generated

    // Call Windows API
    SendInput(1, &input, sizeof(INPUT));
}
```

---

## 8. Memory Management

### Custom Memory Allocator

**File:** `source/SimpleHeap.h`

```cpp
class SimpleHeap
{
public:
    static LPTSTR Alloc(LPCTSTR aString)
    {
        size_t size = _tcslen(aString) + 1;
        LPTSTR mem = (LPTSTR)malloc(size * sizeof(TCHAR));
        if (mem)
            _tcscpy(mem, aString);
        return mem;
    }

    static void Free(void *aPtr)
    {
        free(aPtr);
    }
};
```

### Variable Storage

**File:** `source/var.h`

```cpp
class Var
{
public:
    LPTSTR mName;           // Variable name
    VarAttribType mAttrib;  // Attributes (local, global, static, etc.)

    union {
        __int64 mContentsInt64;   // For integer values
        double mContentsDouble;   // For float values
        struct {
            LPTSTR mCharContents;  // For string values
            size_t mByteLength;    // String length in bytes
            size_t mByteCapacity;  // Allocated capacity
        };
    };

    VarTypeType mType;  // VAR_TYPE_INTEGER, VAR_TYPE_FLOAT, VAR_TYPE_STRING

    // Methods
    void Assign(LPCTSTR aValue);
    void Assign(__int64 aValue);
    void Assign(double aValue);
    void Get(ResultToken &aToken);
};
```

### Object System

**File:** `source/script_object.h`

```cpp
class Object
{
public:
    // Reference counting
    ULONG mRefCount;

    // Properties (key-value pairs)
    KeyValuePair *mFields;
    int mFieldCount;
    int mFieldCapacity;

    // Base object (prototype)
    Object *mBase;

    // Methods
    virtual ResultType Invoke(ResultToken &aResultToken,
                             ExprTokenType &aThisToken,
                             ExprTokenType **aParam,
                             int aParamCount);

    void AddRef() { ++mRefCount; }
    void Release()
    {
        if (--mRefCount == 0)
            delete this;
    }
};
```

---

## 9. Complete Example Flow

### Example Script

```autohotkey
#Requires AutoHotkey v2.0

global counter := 0

^j::  ; Ctrl+J hotkey
{
    counter++
    MsgBox "Counter: " counter
}
```

### Execution Flow (Step-by-Step)

#### 1. Startup

```cpp
_tWinMain()
├── EarlyAppInit()
│   ├── SetErrorMode()
│   ├── global_init()
│   └── Object::CreateRootPrototypes()
├── ParseCmdLineArgs()
├── g_script.LoadFromFile("script.ahk")
│   ├── Parse: #Requires AutoHotkey v2.0
│   ├── Parse: global counter := 0
│   │   └── Create global variable "counter"
│   └── Parse: ^j:: { counter++; MsgBox... }
│       └── Create Hotkey object for Ctrl+J
├── InitForExecution()
│   └── g_script.CreateWindows()
└── MainExecuteScript()
    ├── Hotkey::ManifestAllHotkeysHotstringsHooks()
    │   └── ChangeHookState()
    │       └── CreateThread(HookThreadProc)
    │           ├── SetWindowsHookEx(WH_KEYBOARD_LL)
    │           └── Build lookup tables:
    │               Kvkm[MOD_LCONTROL, 'J'] = hotkey_id
    ├── g_script.AutoExecSection()
    │   └── Execute: counter := 0
    └── MsgSleep(WAIT_FOR_MESSAGES)
        └── Wait for events...
```

#### 2. User Presses Ctrl+J

```cpp
[Hook Thread]
LowLevelKeybdProc(WM_KEYDOWN, VK_CONTROL)
├── UpdateModifierLRState()
│   └── g_modifiersLR_logical |= MOD_LCONTROL
└── CallNextHookEx()  // Pass through

LowLevelKeybdProc(WM_KEYDOWN, 'J')
├── FindHotkeyMatch('J', MOD_LCONTROL)
│   └── Kvkm[MOD_LCONTROL, 'J'] → hotkey_id = 1
├── Hotkey::FindHotkeyByID(1)
│   └── Returns hotkey object for ^j::
├── hk->CriterionAllowsFiring() → true
├── PostMessage(g_hWnd, AHK_HOOK_HOTKEY, hotkey_id, ...)
└── return TRUE  // Suppress key
```

#### 3. Main Thread Receives Message

```cpp
[Main Thread]
MsgSleep()
├── GetMessage(&msg)
│   └── Receives: AHK_HOOK_HOTKEY
├── switch (msg.message)
│   case AHK_HOOK_HOTKEY:
│       hotkey_id = msg.wParam
│       hk = Hotkey::FindHotkeyByID(hotkey_id)
│
│       InitNewThread(priority=0, ...)
│       ├── ++g  // g_array[0] → g_array[1]
│       ├── memcpy(g, &g_default)
│       └── ++g_nThreads
│
│       hk->PerformInNewThreadMadeByCaller()
│       ├── variant = FindVariant()
│       ├── g->mThisHotkey = this
│       └── variant->mCallback->Call()
│           │
│           └── Execute hotkey body:
│               ├── Line 1: counter++
│               │   ├── Get variable "counter" → 0
│               │   ├── Add 1 → 1
│               │   └── Assign to "counter"
│               │
│               └── Line 2: MsgBox "Counter: " counter
│                   ├── Evaluate expression: "Counter: " . counter
│                   │   └── Result: "Counter: 1"
│                   └── BIF_MsgBox(aResultToken, ["Counter: 1"])
│                       └── MessageBox(g_hWnd, "Counter: 1", "AutoHotkey", 0)
│                           └── [Windows shows message box]
│
│       ResumeUnderlyingThread()
│       ├── --g_nThreads
│       └── --g  // g_array[1] → g_array[0]
│
└── Continue message loop...
```

#### 4. User Closes MsgBox

```cpp
MessageBox() returns → IDOK
└── Back to script execution
    └── Hotkey body complete
        └── ResumeUnderlyingThread()
            └── Return to MsgSleep()
                └── Wait for next event...
```

---

## Summary

### Key C++ Mechanisms

1. **Event-Driven Architecture**
   - Main thread runs message loop (MsgSleep)
   - Hook thread intercepts all input
   - Messages passed between threads via PostMessage

2. **Quasi-Threading**
   - Stack of global_struct contexts
   - Cooperative multitasking (not preemptive)
   - Controlled interruption via interruptibility checks

3. **O(1) Hotkey Lookup**
   - Pre-computed 2D arrays indexed by [modifiers][key]
   - Instant hotkey matching without searching

4. **WinAPI Integration**
   - Direct calls throughout the codebase
   - Hooks: SetWindowsHookEx
   - Input: SendInput, keybd_event
   - Windows: FindWindow, SetForegroundWindow
   - GUI: CreateWindowEx, SendMessage

5. **Memory Management**
   - Custom SimpleHeap allocator
   - Reference counting for objects
   - Union types for efficient variable storage

6. **Debugger Integration**
   - Hooks at every line execution
   - Stack tracking via DEBUGGER_STACK_PUSH/POP
   - DBGp protocol over TCP sockets

---

**This is how AutoHotkey v2 works at the C++ level!**

Every keystroke, every hotkey, every command - all orchestrated by this sophisticated C++ interpreter that bridges the gap between high-level AHK scripts and low-level Windows APIs.

---

**Related Files:**
- Full codebase: `/home/user/AutoHotkey/source/`
- Entry point: `/home/user/AutoHotkey/source/AutoHotkey.cpp`
- Hook system: `/home/user/AutoHotkey/source/hook.cpp`
- Event loop: `/home/user/AutoHotkey/source/application.cpp`
- Script engine: `/home/user/AutoHotkey/source/script.cpp`

**Last Updated:** 2025-10-23
