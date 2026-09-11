#Requires AutoHotkey v2.1-alpha.28

; Union via DefineProp Offset — overlapping fields (alpha.24)
Struct Color {
    rgba: UInt32
}
DefineProp(Color.Prototype, "r", {Type: UInt8, Offset: 0})
DefineProp(Color.Prototype, "g", {Type: UInt8, Offset: 1})
DefineProp(Color.Prototype, "b", {Type: UInt8, Offset: 2})
DefineProp(Color.Prototype, "a", {Type: UInt8, Offset: 3})
c := Color()
c.rgba := 0xFF00FF80

; c.r => 128, c.g => 255, c.b => 0, c.a => 255    

MsgBox(
    Format("r: {}, g: {}, b: {}, a: {}", c.r, c.g, c.b, c.a) . "`n",
    "Output.txt"
)