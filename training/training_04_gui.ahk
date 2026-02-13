#Requires AutoHotkey v2.0
#SingleInstance Force

; Training Example 4: Simple GUI Window
; Demonstrates: Window creation, controls, event handling, and user interaction
; Create a new GUI window
MyGui := Gui()
; Add a title
MyGui.Add("Text", "w300 h30 cBlue", "Welcome to My First GUI!")
; Add an edit box (text input)
MyGui.Add("Text", , "Enter your name:")
nameEdit := MyGui.Add("Edit", "w200")
; Add buttons
MyGui.Add("Button", "w90 Default", "Submit").OnEvent("Click", ButtonClick)
MyGui.Add("Button", "w90 x+10 yp", "Clear").OnEvent("Click", ButtonClear)
; Show the window
MyGui.Show("w300", "My First GUI")
; Handle Submit button
ButtonClick(GuiCtrlObj, Info) {
name := nameEdit.Value
if (name = "") {
MsgBox("Please enter your name!")
} else {
MsgBox("Hello, " . name . "!")
}
}
; Handle Clear button
ButtonClear(GuiCtrlObj, Info) {
nameEdit.Value := ""
nameEdit.Focus()  ; Set keyboard focus to the edit box
}
