#Requires AutoHotkey v2.0
#SingleInstance Force

; Training Example 1: Basic Class Definition with Properties
; Demonstrates: Class creation, properties, methods, and object initialization

; Define a simple Person class
class Person {
    ; Constructor - runs when creating a new Person object
    __New(name, age) {
        this.name := name      ; Instance property: name
        this.age := age        ; Instance property: age
    }

    ; Method to display person information
    GetInfo() {
        return this.name . " is " . this.age . " years old"
    }

    ; Method to increment age (birthday)
    HaveBirthday() {
        this.age += 1
    }
}

; Main script - demonstrate the class
MsgBox(Person("Alice", 25).GetInfo())  ; Output: Alice is 25 years old

; Create and modify an object
user := Person("Bob", 30)
user.HaveBirthday()
MsgBox(user.GetInfo())  ; Output: Bob is 31 years old
