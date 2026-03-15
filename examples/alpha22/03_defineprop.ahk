; alpha.22 Feature: DefineProp() function
; New top-level function for defining properties on objects programmatically.
; Complements the existing obj.DefineProp() method.
; Requires: AutoHotkey v2.1-alpha.22+

; --- Basic getter/setter with DefineProp ---

obj := {}

; Define a property with getter and setter
DefineProp(obj, "Name", {
    Get: (this) => this._name ?? "unnamed",
    Set: (this, value) => this._name := value
})

obj.Name := "alpha22"
FileAppend("Name: " obj.Name "`n", "*")  ; => Name: alpha22

; --- Computed property ---

point := { x: 3, y: 4 }

DefineProp(point, "Magnitude", {
    Get: (this) => Sqrt(this.x ** 2 + this.y ** 2)
})

FileAppend("Magnitude: " point.Magnitude "`n", "*")  ; => Magnitude: 5.0

; --- Read-only property ---

config := {}

DefineProp(config, "Version", {
    Get: (*) => "2.1-alpha.22"
})

FileAppend("Version: " config.Version "`n", "*")

; --- Using DefineProp on a class prototype ---

class Counter {
    __New() {
        this._count := 0
    }
}

; Add a dynamic property to all Counter instances
DefineProp(Counter.Prototype, "Count", {
    Get: (this) => this._count,
    Set: (this, value) {
        if value < 0
            throw ValueError("Count cannot be negative")
        this._count := value
    }
})

c := Counter()
c.Count := 10
FileAppend("Counter: " c.Count "`n", "*")  ; => Counter: 10

; --- Advantage over method syntax ---
; DefineProp as a function is useful when the target object
; is not known at author-time (e.g., dynamically generated objects)

AddTimestamp(target, propName) {
    DefineProp(target, propName, {
        Get: (*) => FormatTime(, "yyyy-MM-dd HH:mm:ss")
    })
}

record := {}
AddTimestamp(record, "CreatedAt")
FileAppend("Timestamp: " record.CreatedAt "`n", "*")
