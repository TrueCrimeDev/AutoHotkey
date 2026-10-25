; alpha.37: DllCall/ComCall "Str", "*" and "P" parameters accept unset as null
;
; Many Win32 functions take an optional pointer: pass NULL and they skip that
; output, query a size, or mean "the current module". That used to need
; "Ptr", 0 and a lie about the parameter's type. Now the typed parameter
; keeps its type and unset is the null pointer.
;
; Two distinct spellings:
;   "UInt*", unset       passes NULL (no variable involved)
;   "UInt*", &v := unset passes the address of v (v receives the output)
;
; Before alpha.37 both "Str", unset and "Int*", unset threw
; "Missing a required parameter."
;
; Run: bin\AutoHotkey64Console.exe examples\alpha37\03_dllcall_unset_null.ahk
#Requires AutoHotkey v2.1-alpha.37

; --- 1. A size query, then the real call ----------------------------------------
; GetCurrentDirectoryW(0, NULL) returns the length needed, including the
; terminator.
len := DllCall("GetCurrentDirectoryW", "UInt", 0, "Str", unset, "UInt")
buf := Buffer(len * 2)
DllCall("GetCurrentDirectoryW", "UInt", len, "Ptr", buf, "UInt")
Print("GetCurrentDirectoryW needs {} chars: {}", len - 1, StrGet(buf))

; --- 2. NULL means "this module" ---------------------------------------------------
hSelf := DllCall("GetModuleHandleW", "Str", unset, "Ptr")
hUser := DllCall("GetModuleHandleW", "Str", "user32.dll", "Ptr")
Print("GetModuleHandleW(NULL) = 0x{:X}  (user32 = 0x{:X})", hSelf, hUser)

; --- 3. Skip an output you do not want --------------------------------------------
; GetWindowThreadProcessId returns the thread id and writes the process id
; through its second parameter, which may be NULL.
hwnd := DllCall("GetConsoleWindow", "Ptr") || DllCall("GetDesktopWindow", "Ptr")
tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", unset, "UInt")
Print("thread id only: {}", tid)
tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid := 0, "UInt")
Print("thread id {} and process id {}", tid, pid)

; --- 4. The null pointer really is 0, not a pointer to 0 -----------------------------
; _wcsdup(NULL) returns NULL; _wcsdup("") allocates an empty string.
Print("_wcsdup(NULL) = {}", DllCall("msvcrt\_wcsdup", "Str", unset, "Ptr"))
p := DllCall("msvcrt\_wcsdup", "Str", "", "Ptr")
Print("_wcsdup(`"`") = 0x{:X} (freed)", p)
DllCall("msvcrt\free", "Ptr", p)

; --- 5. Optional parameters in a wrapper -------------------------------------------
; A wrapper with an optional by-reference parameter passes NULL when the
; caller did not ask for the output, and the variable's address when it did.
WindowThread(hwnd, &pid?) {
    if !IsSet(pid)
        return DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", unset, "UInt")
    return DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
}
Print("WindowThread(hwnd) = {}", WindowThread(hwnd))
Print("WindowThread(hwnd, &pid) = {}, pid = {}", WindowThread(hwnd, &pid2 := 0), pid2)
