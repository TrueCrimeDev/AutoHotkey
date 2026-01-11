#Requires AutoHotkey v2.0
#SingleInstance Force

; Training Example 5: String Processing with Regular Expressions
; Demonstrates: Pattern matching, text extraction, replacement, and validation
; Example 1: Extract email addresses
text := "Contact us at support@example.com or sales@company.net"
if (RegExMatch(text, "(\w+@[\w.]+)", match)) {
MsgBox("Found email: " . match[1])  ; Output: Found email: support@example.com
}
; Example 2: Replace all whitespace with underscores
sentence := "Hello   World   Test"
cleaned := RegExReplace(sentence, "\s+", "_")
MsgBox("Original: " . sentence . "`nCleaned: " . cleaned)
; Example 3: Validate a phone number (basic format: 123-456-7890)
phoneNumber := "555-123-4567"
pattern := "^\d{3}-\d{3}-\d{4}$"  ; ^ = start, $ = end, \d = digit, {n} = exactly n times
if (RegExMatch(phoneNumber, pattern)) {
MsgBox("Valid phone number!")
} else {
MsgBox("Invalid phone number format!")
}
; Example 4: Extract numbers from text
text2 := "I have 42 apples and 17 oranges"
matches := []
while (RegExMatch(text2, "\d+", &match, A_Index = 1 ? 1 : InStr(text2, match[0]) + StrLen(match[0]))) {
matches.Push(match[0])
if (matches.Length >= 2) break
}
MsgBox("Found numbers: " . matches[1] . " and " . matches[2])  ; Output: Found numbers: 42 and 17
