#Requires AutoHotkey v2.1-alpha.30
; test_language.ahk -- fork/alpha language-level behaviors. Verified against
; 2.1-alpha.30+Console on 2026-07-09. Backlog items #3 and #4.
#Include ..\Assert.ahk

; ---- StrGet(x, 0): length 0 yields an empty String (alpha change) ----
r := StrGet(0, 0)
Assert.eq(Type(r), "String", "StrGet(ptr, 0) returns a String")
Assert.eq(r, "", "StrGet(ptr, 0) is the empty string")

; ---- Format() dispatch: underpins the variadic Print() BIF ----
Assert.eq(Format("x={}", 42), "x=42", "Format positional {} substitution")
Assert.eq(Format("{1}-{1}", "a"), "a-a", "Format {1} index reuse")
Assert.eq(Format("{2},{1}", "a", "b"), "b,a", "Format explicit index order")
Assert.eq(Format("plain text"), "plain text", "Format single arg is literal (no {} present)")

; ---- maybe-call: (fn?)() invokes only when the var is set ----
; Object accumulator avoids the global-write restriction on fat-arrow bodies.
hits := []
fn := () => hits.Push(1)
(fn?)()
Assert.eq(hits.Length, 1, "(fn?)() invokes when the var is set")
unsetFn := unset
(unsetFn?)()
Assert.eq(hits.Length, 1, "(unsetFn?)() is a no-op when the var is unset")

Assert.Summary()
