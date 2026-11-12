; alpha.38: user-defined Ptr subclasses are constructed
;
; A pointer class created with Class(X.Ptr) can define its own __Value, and a
; struct field of that type now reads through it. That makes "string pointer"
; field types possible: the field holds an address, and reading it returns
; the string.
;
; Before alpha.38 the subclass was never constructed: reading the field
; returned the pointed-to X instance and the custom __Value never ran.
; Subclassing needs Class(X.Ptr) for now; "class Y extends X.Ptr" is still
; rejected with "Invalid base class."
;
; Run: bin\AutoHotkey64Console.exe examples\alpha38\04_custom_pointer_types.ahk
#Requires AutoHotkey v2.1-alpha.38

; --- 1. Two string-pointer types ---------------------------------------------
; Inside __Value, this.Ptr is the address of the field itself, so the string's
; address is the pointer-sized value stored there. A null pointer reads as "".
StringPointer(elementClass, encoding) {
    cls := Class(elementClass.Ptr)
    DefineProp(cls.Prototype, "__Value", {Get: (this) => (p := NumGet(this.Ptr, "Ptr")) ? StrGet(p, encoding) : ""})
    return cls
}
PWSTR := StringPointer(UInt16, "UTF-16")   ; wchar_t*
PSTR  := StringPointer(UInt8, "CP0")       ; char* in the ANSI code page

; --- 2. A Win32 struct with LPWSTR fields ------------------------------------
; NetWkstaGetInfo level 100 allocates a WKSTA_INFO_100 and returns its address.
struct WKSTA_INFO_100 {
    platform_id  : UInt32
    computername : PWSTR
    langroup     : PWSTR
    ver_major    : UInt32
    ver_minor    : UInt32
}
if !DllCall("netapi32\NetWkstaGetInfo", "Ptr", 0, "UInt", 100, "Ptr*", &p := 0, "UInt") {
    info := WKSTA_INFO_100.At(p)
    Print("computer {} in {}, Windows {}.{}  (A_ComputerName agrees: {})"
        , info.computername, info.langroup, info.ver_major, info.ver_minor, info.computername = A_ComputerName)
    DllCall("netapi32\NetApiBufferFree", "Ptr", p)
}

; --- 3. A C runtime struct with char* fields ---------------------------------
; localeconv() returns a pointer to the C runtime's static struct lconv.
struct lconv {
    decimal_point     : PSTR
    thousands_sep     : PSTR
    grouping          : PSTR
    int_curr_symbol   : PSTR
    currency_symbol   : PSTR
}
lc := lconv.At(DllCall("msvcrt\localeconv", "Ptr"))
Print('C locale: decimal point "{}", thousands separator "{}", currency "{}"'
    , lc.decimal_point, lc.thousands_sep, lc.currency_symbol)

; --- 4. Writing the field takes a view of the string ---------------------------
; The getter is custom; the setter is still the pointer class's own, which
; takes an instance of the target class. UInt16.At(buffer) (02) is one: the
; field stores its address and keeps it, and the Buffer, alive. Reading goes
; back through PWSTR's __Value.
struct NamedValue {
    name  : PWSTR
    value : Int32
}
text := Buffer(StrPut("width", "UTF-16") * 2)
StrPut("width", text, "UTF-16")
nv := NamedValue()
nv.name := UInt16.At(text)
nv.value := 640
Print("{} = {}", nv.name, nv.value)
Print("an empty field reads as {}", NamedValue().name = "" ? "an empty string" : "something else")
