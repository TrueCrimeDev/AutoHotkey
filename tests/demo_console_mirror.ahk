#Requires AutoHotkey v2
; Live demo: hooks installed, keys sent to our own GUI, then KeyHistory/ListVars to stdout.

InstallKeybdHook()
InstallMouseHook()

g := Gui("+AlwaysOnTop", "Console Mirror Demo")
g.AddEdit("w300 h80")
g.Show()
if (WinWaitActive("Console Mirror Demo", , 2)) {
    Send("hello{Enter}ahk")
    Sleep(200)
}
g.Destroy()

demoVar := "it works"
answer := 42

Print("---- KeyHistory ----")
KeyHistory()
Print("---- ListVars ----")
ListVars()
Print("---- ListHotkeys ----")
ListHotkeys()
ExitApp(0)

F12:: KeyHistory()        ; dump key history on demand
^!p:: Print("Ctrl+Alt+P pressed")
#h:: ListHotkeys()        ; Win+H: dump the hotkey table
~LButton:: return         ; pass-through mouse hotkey
