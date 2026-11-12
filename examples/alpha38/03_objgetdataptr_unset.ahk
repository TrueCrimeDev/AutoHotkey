; alpha.38: ObjGetDataPtr returns unset instead of throwing
;
; For an object without structured data ({}, [], Map(), a Buffer, a
; Prototype), ObjGetDataPtr now returns unset. That makes it a test as well
; as an accessor: "does this object have typed fields, and where are they?"
; A non-object still throws TypeError.
;
; Before alpha.38 every one of those objects threw Error "Failed", so a
; generic helper needed try/catch around each call.
;
; Run: bin\AutoHotkey64Console.exe examples\alpha38\03_objgetdataptr_unset.ahk
#Requires AutoHotkey v2.1-alpha.38

struct POINT {
    x : Int32
    y : Int32
}
class Sample {          ; an ordinary class with typed fields
    id    : Int32
    score : Float64
    label := "sample"   ; an ordinary property, not part of the data
}

; --- 1. One "address of" helper for every kind of argument ---------------------
; Struct instances and typed-field objects give their data pointer, anything
; with a Ptr property (Buffer) gives that, and a number is already an address.
AddressOf(v) {
    if !IsObject(v)
        return v
    return ObjGetDataPtr(v) ?? v.Ptr
}
pt := POINT(3, 4)
buf := Buffer(8, 0)
Print("POINT {}, Buffer {}, number {}", AddressOf(pt) = pt.Ptr, AddressOf(buf) = buf.Ptr, AddressOf(1234))

; --- 2. Branch on whether an object carries raw data -------------------------
; A dumper that prints typed objects as bytes and everything else as JSON.
Dump(v) {
    if IsSet(ObjGetDataPtr(v)) {
        p := ObjGetDataPtr(v), n := ObjGetDataSize(v), hex := ""
        loop n
            hex .= Format("{:02X} ", NumGet(p, A_Index - 1, "UChar"))
        return Type(v) " bytes: " RTrim(hex)
    }
    return Type(v) " json: " JSON.Stringify(v)
}
s := Sample()
s.id := 7, s.score := 0.5
for v in [pt, s, {name: "plain"}, [1, 2, 3], Map("k", "v")]
    Print(Dump(v))

; --- 3. A default instead of an error ----------------------------------------
Print("ObjGetDataPtr({{}}) ?? 0 = {}", ObjGetDataPtr({}) ?? 0)

; --- 4. A non-object is still a programming error ----------------------------
try ObjGetDataPtr(42)
catch TypeError as e
    Print("ObjGetDataPtr(42): {}", e.Message)
