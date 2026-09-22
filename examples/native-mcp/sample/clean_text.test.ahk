#Requires AutoHotkey v2.1-alpha.31
#Include TextTools.ahk
; Minimal standalone suite: exit 14 is the fork's test-failure convention.
failures := 0
CheckEqual(CleanText("  hello`t world  "), "hello world", "collapse whitespace")
CheckEqual(CleanText("one`r`ntwo"), "one two", "flatten line breaks")
CheckEqual(CleanText("  café   日本  "), "café 日本", "preserve Unicode")
rejected := false
try {
    CleanText(" `t ")
} catch ValueError {
    rejected := true
}
CheckEqual(rejected, true, "reject blank input")
if A_Args.Length && A_Args[1] = "--fail"
    CheckEqual(CleanText("hello"), "wrong on purpose", "intentional failure")
Print("Failures: {}", failures)
ExitApp(failures ? 14 : 0)

CheckEqual(actual, expected, label) {
    global failures
    if actual == expected {
        Print("PASS {}", label)
    } else {
        failures += 1
        Print("FAIL {}: expected [{}], got [{}]", label, expected, actual)
    }
}
