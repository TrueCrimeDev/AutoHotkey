#Requires AutoHotkey v2.1-alpha.17
#SingleInstance Force

; Import reusable helpers as modules. Importing the module object exposes
; each export as a read-only member and runs the module body so Array prototype
; extensions are registered automatically.
Import ArrayHelpers
Import StringHelpers as Strings

; Reformat a noisy string using StringHelpers.
raw := "  auto`n`thotkey   utilities  "
clean := Strings.CollapseWhitespace(raw)

MsgBox("Collapsed whitespace:`n'" . clean . "'")
MsgBox("Title case:`n" . Strings.ToTitleCase(clean))

; Join arrays through either the exported function or the prototype method that
; the module registers. Both approaches are read-only bindings to the same helper.
words := ["one", "two", "three"]
MsgBox("Module Join:`n" . ArrayHelpers.Join(words, " - "))
MsgBox("Prototype Join:`n" . words.Join(" | "))

; Split returns a populated array and can also fill an existing target.
split := ArrayHelpers.Split("alpha,beta,gamma", ",")
MsgBox("Split -> Join:`n" . split.Join(" "))

bucket := ["seed"]
ArrayHelpers.Split("delta,epsilon", ",", bucket)
MsgBox("Target array after Split:`n" . bucket.Join(" + "))
