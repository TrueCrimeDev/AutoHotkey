#Requires AutoHotkey v2.0
#SingleInstance Force

; Training Example 3: Map Data Structure Usage
; Demonstrates: Map creation, key-value storage, iteration, and lookup
; Create a Map for storing product information
products := Map()
; Add key-value pairs
products["apple"] := 0.99
products["banana"] := 0.59
products["orange"] := 1.29
products["grape"] := 2.49
; Lookup a value by key
appleCost := products["apple"]
MsgBox("Apple costs: $" . appleCost)  ; Output: Apple costs: $0.99
; Check if a key exists
if (products.Has("banana")) {
MsgBox("Banana found: $" . products["banana"])
}
; Iterate through all items
inventory := "Available Products:`n"
for name, price in products {
inventory .= name . ": $" . price . "`n"
}
MsgBox(inventory)
; Update a value
products["apple"] := 1.19  ; Price increased
MsgBox("New apple price: $" . products["apple"])
; Count total items
MsgBox("Total products: " . products.Count)  ; Output: Total products: 4
