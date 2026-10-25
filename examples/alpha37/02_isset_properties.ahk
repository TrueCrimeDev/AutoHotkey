; alpha.37: IsSet(a.b) and IsSet(f()) imply a final ?
;
; IsSet used to accept only a variable or an explicitly optional expression
; (IsSet(o.b?)). Now a property access or a call without the ? is read as if
; it had one, so "is this property there?" and "did this call return a value?"
; are one short test each. Only the final access is optional: IsSet(o.a.b)
; still throws if o.a itself is missing.
;
; Before alpha.37, IsSet(o.prop) was a load-time error:
; "IsSet requires a variable or unset expression."
;
; Run: bin\AutoHotkey64Console.exe examples\alpha37\02_isset_properties.ahk
#Requires AutoHotkey v2.1-alpha.37

; --- 1. Optional settings on a plain object -----------------------------------
defaults := {retries: 3, timeout: 30}
user := {timeout: 5}

Setting(name) => IsSet(user.%name%) ? user.%name% : defaults.%name%
Print("retries = {}  timeout = {}", Setting("retries"), Setting("timeout"))

; --- 2. A function that returns unset for "no result" ------------------------
; A finder can return nothing instead of a sentinel such as 0 or "", and the
; caller tests the call itself.
FindFirst(items, pred) {
    for item in items
        if pred(item)
            return item
    ; falls off the end: returns unset
}
nums := [4, 9, 16, 23]
Print("first > 10: {}", IsSet(FindFirst(nums, x => x > 10)) ? FindFirst(nums, x => x > 10) : "none")
Print("first > 50: {}", IsSet(FindFirst(nums, x => x > 50)) ? FindFirst(nums, x => x > 50) : "none")

; --- 3. Feature detection on objects you did not write -----------------------
class Plain {
}
class Loud {
    Describe() => "I can describe myself"
}
for obj in [Plain(), Loud()]
    Print("{}: {}", Type(obj), IsSet(obj.Describe) ? obj.Describe() : "(no Describe)")

; --- 4. Optional handler slots (pairs with 05_safer_errors.ahk) --------------
; A getter that returns unset is an empty slot. IsSet(b.onClick) reads it as
; "not wired"; the wired instance supplies a value through DefineProp. Calling
; btn.onClick() invokes the getter's value as a method, so the handler receives
; the button as its first parameter.
class Button {
    onClick => unset
}
b := Button()
wired := Button()
wired.DefineProp("onClick", {Get: (*) => (self) => Type(self) " clicked"})
for name, btn in Map("b", b, "wired", wired)
    Print("{}.onClick: {}", name, IsSet(btn.onClick) ? btn.onClick() : "not wired")

; --- 5. Only the last access is optional ----------------------------------------
cfg := {net: {proxy: "proxy.local"}}
Print("cfg.net.proxy set: {}", IsSet(cfg.net.proxy))
Print("cfg.net.port set:  {}", IsSet(cfg.net.port))
try IsSet(cfg.disk.path)                 ; cfg.disk does not exist
catch PropertyError as e
    Print("IsSet(cfg.disk.path): {}", e.Message)
Print("guarded: {}", IsSet(cfg.disk) && IsSet(cfg.disk.path) ? "set" : "not set")

; The explicit form still works and means the same thing.
Print("IsSet(cfg.net.proxy?) = {}", IsSet(cfg.net.proxy?))
