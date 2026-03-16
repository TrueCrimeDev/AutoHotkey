; ============================================================
; alpha.21 Feature: !~= (not-RegExMatch) operator
; ============================================================
; Previously: a ~!= b   (alpha.20)
; Now:        a !~= b   (alpha.21)
;
; Equivalent to: !(a ~= b)
; Returns true when the string does NOT match the regex.
; ============================================================

; --- Basic usage ---
name := "AutoHotkey"

if name !~= "^Python"
    MsgBox name ' is NOT Python (correct!)'

if name ~= "^Auto"
    MsgBox name ' starts with "Auto" (correct!)'

; --- Filtering a list ---
fruits := ["apple", "banana", "cherry", "avocado", "blueberry"]
non_a_fruits := []

for fruit in fruits
{
    if fruit !~= "^a"  ; doesn't start with 'a'
        non_a_fruits.Push(fruit)
}

result := ""
for fruit in non_a_fruits
    result .= (result ? ", " : "") fruit
MsgBox "Fruits not starting with 'a': " result
; Expected: banana, cherry, blueberry

; --- Validation example ---
ValidateEmail(addr)
{
    if addr !~= "^\w+@\w+\.\w+$"
        return "Invalid email: " addr
    return "Valid email: " addr
}

MsgBox ValidateEmail("user@example.com")   ; Valid
MsgBox ValidateEmail("not-an-email")       ; Invalid

; --- Combining ~= and !~= for cleaner conditionals ---
input := "Hello World 123"

; Old way (alpha.20 and earlier):
;   if !(input ~= "\d+")
;       MsgBox "no digits"
;
; New way (alpha.21):
if input !~= "\d+"
    MsgBox "No digits found"
else
    MsgBox "Contains digits"
