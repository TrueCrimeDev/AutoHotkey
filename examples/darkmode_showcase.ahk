/*
DarkMode v2 Showcase — tests all dark-styled controls
*/
#Requires AutoHotkey v2.1-alpha.28
#Include ..\Lib\DarkMode.ahk

myGui := DarkGui("+Resize", "DarkMode v2 Showcase")

myGui.Add("Text", "x16 y16 w400 Section", "DarkMode v2 — All Controls")

myGui.Add("Button", "xs y+12 w120 h32 +Accent", "Accent Button")
myGui.Add("Button", "x+8 yp w120 h32", "Default Button")

myGui.Add("Text", "xs y+16", "Edit:")
myGui.Add("Edit", "xs y+4 w300 h24", "Dark text input")

myGui.Add("Text", "xs y+12", "ComboBox:")
myGui.Add("ComboBox", "xs y+4 w200", ["Option 1", "Option 2", "Option 3"])

myGui.Add("CheckBox", "xs y+12", "Dark checkbox")
myGui.Add("Radio", "xs y+8", "Radio option A")
myGui.Add("Radio", "xs y+4", "Radio option B")

myGui.Add("Text", "xs y+12", "ListView:")
lv := myGui.Add("ListView", "xs y+4 w400 h120", ["Name", "Type", "Size"])
lv.Add(, "DarkMode.ahk", "AHK", "1026 lines")
lv.Add(, "Alpha26_Example.ahk", "AHK", "180 lines")
lv.Add(, "README.md", "Markdown", "250 lines")

myGui.Add("Text", "xs y+12", "Slider:")
myGui.Add("Slider", "xs y+4 w300 Range0-100", 50)

myGui.Add("Text", "xs y+12", "Progress:")
myGui.Add("Progress", "xs y+4 w300 h20", 65)

myGui.Add("GroupBox", "xs y+16 w200 h80", "Settings")

myGui.Add("Text", "x240 y+-60", "TreeView:")
tv := myGui.Add("TreeView", "xp y+4 w160 h100")
p1 := tv.Add("Root Item")
tv.Add("Child 1", p1)
tv.Add("Child 2", p1)
tv.Add("Another Root")

myGui.Add("Text", "xs y+16", "ListBox:")
myGui.Add("ListBox", "xs y+4 w200 h80", ["Item Alpha", "Item Beta", "Item Gamma", "Item Delta"])

myGui.OnEvent("Close", (*) => ExitApp())
myGui.Show("w450")
