#Requires AutoHotkey v2.0
#SingleInstance Force

; Training Example 2: Array Operations and Filtering
; Demonstrates: Array creation, iteration, filtering, and transformation
; Create an array of numbers
numbers := [10, 25, 8, 42, 15, 33, 7, 50]
; Filter: Keep only numbers greater than 20
largeNumbers := []
for num in numbers {
if (num > 20) {
largeNumbers.Push(num)  ; Add to new array
}
}
; Display filtered results
result := "Numbers > 20: "
for num in largeNumbers {
result .= num . " "
}
MsgBox(result)  ; Output: Numbers > 20: 25 42 33 50
; Find: Get first even number
evenNumber := ""
for num in numbers {
if (Mod(num, 2) = 0) {  ; Mod returns remainder
evenNumber := num
break
}
}
MsgBox("First even number: " . evenNumber)  ; Output: First even number: 10
; Transform: Double all numbers
doubled := []
for num in numbers {
doubled.Push(num * 2)
}
MsgBox("Doubled: " . doubled[1] . ", " . doubled[2])  ; First two doubled values
