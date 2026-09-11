; ============================================================
; alpha.21 Feature: #Import from file
; ============================================================
; Syntax: #Import "path/to/file.ahk" {*}      ; bind every name the file defines
;         #Import "path/to/file.ahk"          ; bind only the module object
;
; When a file contains a single default module, this imports
; it directly. For files with named modules, use:
;   #Import "file.ahk:ModuleName" {Name, ...}
;
; This example imports from the companion files:
;   - lib/StringUtils.ahk  (single-module file)
;   - lib/Collections.ahk  (multi-module file)
; ============================================================

; Import entire module from a file
#Import "lib/StringUtils.ahk" {*}

; Import a specific named module from a multi-module file
#Import "lib/Collections.ahk:Stack" {Stack}

; --- Use StringUtils ---
original := "  Hello, World!  "
MsgBox "Trimmed + upper: " ToUpper(Trim(original))
MsgBox "Repeat: " Repeat("AHK ", 3)
MsgBox "Reverse: " Reverse("desserts")  ; "stressed"

; --- Use Stack ---
s := Stack()
s.Push("first")
s.Push("second")
s.Push("third")

MsgBox "Stack size: " s.Size()
MsgBox "Popped: " s.Pop()       ; "third"
MsgBox "Peek: " s.Peek()        ; "second"
MsgBox "Stack size after pop: " s.Size()
