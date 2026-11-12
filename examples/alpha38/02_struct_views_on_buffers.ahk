; alpha.38: Struct.At and ObjCreateWithDataPtr take a Buffer
;
; Either function now accepts any object with a Ptr property (a Buffer, a
; struct, a File-read block) in place of a raw address, and the view keeps
; that object alive. StructClass.At also accepts addresses below 65536, which
; Win32 uses for resource IDs (MAKEINTRESOURCE) and other small handles.
;
; Before alpha.38, At(buf) threw "Parameter #1 of Struct.At is invalid.",
; ObjCreateWithDataPtr(cls, buf) treated the Buffer object itself as the
; address (exit 11 on the first read), and At(32516) was rejected.
;
; Run: bin\AutoHotkey64Console.exe examples\alpha38\02_struct_views_on_buffers.ahk
#Requires AutoHotkey v2.1-alpha.38

; --- 1. Parse a binary header straight out of a Buffer -----------------------
; The first 4 KB of the running engine's .exe hold its DOS and PE headers.
struct IMAGE_DOS_HEADER {
    e_magic  : UInt16
    _unused  : UInt16[29]
    e_lfanew : Int32           ; file offset of the "PE\0\0" signature
}
struct IMAGE_FILE_HEADER {
    Machine          : UInt16
    NumberOfSections : UInt16
    TimeDateStamp    : UInt32
}
buf := Buffer(4096)
f := FileOpen(A_AhkPath, "r"), f.RawRead(buf), f.Close()

dos := IMAGE_DOS_HEADER.At(buf)                  ; a view of buf, no copy
sig := StrGet(buf.Ptr + dos.e_lfanew, 4, "CP0")
pe := IMAGE_FILE_HEADER.At(buf.Ptr + dos.e_lfanew + 4)
machines := Map(0x14C, "x86", 0x8664, "x64", 0xAA64, "ARM64")
Print("{}: magic {:X}, signature {}, machine {} ({:X}), {} sections"
    , A_AhkPath, dos.e_magic, sig, machines.Get(pe.Machine, "?"), pe.Machine, pe.NumberOfSections)

; --- 2. The view keeps its Buffer alive --------------------------------------
; The Buffer below exists only inside the function. The returned view holds a
; reference to it, so reading after the function returns is safe.
MakeCounter(start) {
    local b := Buffer(4, 0)
    NumPut("Int", start, b)
    return Int32.At(b)
}
c := MakeCounter(100)
c.__Value += 1
Print("counter backed by a function-local Buffer: {}", c.__Value)

; --- 3. An ordinary class over existing memory -------------------------------
; ObjCreateWithDataPtr skips __New and field initializers and maps the typed
; properties onto the Buffer, so methods and properties work on raw data.
class Pair {
    a : Int32
    b : Int32
    Sum => this.a + this.b
}
pairs := Buffer(16, 0)
NumPut("Int", 3, "Int", 4, "Int", 10, "Int", 20, pairs)
first := ObjCreateWithDataPtr(Pair, pairs)
second := ObjCreateWithDataPtr(Pair, {Ptr: pairs.Ptr + 8})   ; any object with Ptr
Print("pairs in one Buffer: {} and {}", first.Sum, second.Sum)

; --- 4. Small addresses: resource IDs ----------------------------------------
; IDI_INFORMATION is MAKEINTRESOURCE(32516): a pointer-typed parameter that
; carries a number. UInt16.At(32516) builds that "pointer" without reading it.
IDI_INFORMATION := UInt16.At(32516)
hIcon := DllCall("LoadIconW", "Ptr", 0, UInt16.Ptr, IDI_INFORMATION, "Ptr")
Print("LoadIconW(NULL, IDI_INFORMATION) returned a handle: {}", hIcon != 0)
nothing := Int32.At(0)
Print("Int32.At(0) is a null view (Ptr = {}); only reading a field would fault", nothing.Ptr)

; --- 5. Something without Ptr is still an error ------------------------------
try IMAGE_DOS_HEADER.At({})
catch Error as e
    Print("At({{}}): {}", e.Message)
