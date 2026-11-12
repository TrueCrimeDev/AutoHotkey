; alpha.38: open structures
;
; A struct's field offsets and total size are no longer calculated while it
; is being defined. The structure stays "open" until something needs its
; layout: an instance, a struct that embeds or extends it, ObjGetDataSize on
; its Prototype, or its use as a DllCall/CallbackCreate type. After that it
; is closed and takes no new typed properties.
;
; Before alpha.38, defining Link (which points back to List) before List
; (which embeds a Link) failed at class initialization with "Parameter #3
; invalid.", because List's first field needed Link's unfinished size.
;
; Run: bin\AutoHotkey64Console.exe examples\alpha38\01_open_structures.ahk
#Requires AutoHotkey v2.1-alpha.38

; --- 1. Structs that refer to each other, in either order ---------------------
; A list header embeds its first link, and every link points back to the list
; that owns it. Link is written first and names List before List exists.
struct Link {
    owner : List.Ptr
    value : Int32
}
struct List {
    head  : Link
    count : Int32
}
lst := List()
lst.head.value := 42
lst.count := 1
Print("List is {} bytes, Link is {}; head.value = {}", ObjGetDataSize(List.Prototype), ObjGetDataSize(Link.Prototype), lst.head.value)

; --- 2. Build a layout from data, inspect it, then close it -------------------
; Fields come from a table, as they would from a header parser or a schema.
; While the structure is open, GetOwnPropDesc reports only what was asked for:
; an Offset given by name stays a name, and Pack appears when it was set.
schema := [
    ["kind",   Int8,  {}],
    ["id",     Int32, {Pack: 1}],        ; packed right after kind
    ["tag",    Int16, {Offset: "kind"}], ; overlays kind
]
Record := Class(Struct)
for f in schema {
    desc := f[3].Clone()
    desc.Type := f[2]
    DefineProp(Record.Prototype, f[1], desc)
}
Describe(name) {
    d := Object.Prototype.GetOwnPropDesc.Call(Record.Prototype, name)
    return Format("{}: Offset={} Pack={}", name
        , d.HasOwnProp("Offset") ? d.Offset : "(not yet)", d.HasOwnProp("Pack") ? d.Pack : "-")
}
for f in schema
    Print("open    {}", Describe(f[1]))

; ObjGetDataSize closes the structure and returns the padded size: kind@0,
; id@1 (Pack 1), tag@0, and the Int16 aligns the whole record to 2 bytes.
Print("ObjGetDataSize(Record.Prototype) = {}", ObjGetDataSize(Record.Prototype))
for f in schema
    Print("closed  {}", Describe(f[1]))

; --- 3. The size includes trailing padding before any instance exists ---------
; Alpha.37 returned 5 here until the first instance was created, then 8.
struct Header {
    length : Int32
    flags  : Int8
}
Print("Header: ObjGetDataSize = {}, instance Size = {}", ObjGetDataSize(Header.Prototype), Header().Size)

; --- 4. Closed means closed --------------------------------------------------
; Both of these were accepted silently by alpha.37.
try DefineProp(Record.Prototype, "extra", {Type: Int8})
catch Error as e
    Print("adding a field after closing: {}", e.Message)
Draft := Class(Struct)
try DefineProp(Draft.Prototype, "x", {Type: Int32, Pack: 3})
catch Error as e
    Print("Pack: 3 (only 0, 1, 2, 4 or 8): {}", e.Message)
