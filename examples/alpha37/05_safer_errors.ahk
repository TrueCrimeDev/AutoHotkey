; alpha.37: four cases that used to crash or write memory now throw
;
;   a.b() when a.b => unset         -> UnsetError   (was: exit 11, invalid memory access)
;   a.b[c] when a.b is a method     -> PropertyError (was: returned silently)
;   NumGet/NumPut with a bad type   -> ValueError   (was: read/wrote a pointer-sized integer)
;   DllCall(..., IntPtr, obj, ...)  -> TypeError    (was: exit 11)
;
; Each is a catchable Error, so a script can validate dynamic input instead of
; dying. This file also shows the fork's fix for an alpha.37 regression: a
; getter that throws keeps its own exception when called as a method.
;
; Run: bin\AutoHotkey64Console.exe examples\alpha37\05_safer_errors.ahk
#Requires AutoHotkey v2.1-alpha.37

; --- 1. Optional hooks: an unset getter is an empty slot ----------------------
class Pipeline {
    ; Hooks default to "nothing". Subclasses or instances supply real callables.
    onStart => unset
    onItem  => unset
    onDone  => unset

    Run(items) {
        this.Fire("onStart")
        for item in items
            this.Fire("onItem", item)
        this.Fire("onDone", items.Length)
    }

    ; Fire a hook that may be empty: IsSet(this.%name%) reads the slot without
    ; calling it. this.%name%(args*) then calls the slot's value as a method,
    ; so every hook receives the pipeline as its first parameter.
    Fire(name, args*) {
        if IsSet(this.%name%)
            this.%name%(args*)
    }
}
class LoggingPipeline extends Pipeline {
    onItem => (self, item) => Print("  item {}", item)
    onDone => (self, n) => Print("  done, {} items", n)
}
Print("Pipeline with no hooks:")
Pipeline().Run([1, 2])
Print("LoggingPipeline:")
LoggingPipeline().Run(["a", "b", "c"])

; Calling an empty slot directly is an ordinary error now.
try Pipeline().onStart()
catch UnsetError as e
    Print("Pipeline().onStart(): {}: {}", Type(e), e.Message)

; --- 2. A method is not an indexable property --------------------------------
class Grid {
    Cell(i) => i * 10
}
try Grid().Cell[2]
catch PropertyError as e
    Print("Grid().Cell[2]: {}", e.Message)
Print("Grid().Cell(2) = {}", Grid().Cell(2))

; --- 3. Validate NumGet/NumPut type names from data --------------------------
layout := Map("version", "UShort", "flags", "UInt", "ratio", "Quad")   ; "Quad" is not a type
buf := Buffer(16, 0)
offset := 0
for name, kind in layout {
    try {
        NumPut(kind, 1, buf, offset)
        Print("{} as {}: ok at offset {}", name, kind, offset)
        offset += kind ~= "i)Short" ? 2 : 4
    } catch ValueError as e
        Print("{} as {}: {}", name, kind, e.Message)
}

; --- 4. DllCall rejects an object where a pointer-sized integer is expected --
try DllCall("msvcrt\abs", IntPtr, {}, "Int")
catch TypeError as e
    Print("DllCall(IntPtr, {{}}): {}", e.Message)

; --- 5. Fork fix: a throwing getter keeps its exception when called ---------------
class Guarded {
    handler {
        get {
            throw ValueError("handler is not configured")
        }
    }
}
try Guarded().handler()
catch Error as e
    Print("Guarded().handler(): {}: {}", Type(e), e.Message)
; Upstream alpha.37 reported UnsetError "No value was returned." here, hiding
; the real message; the fork (a911f73d) restores the ValueError.
