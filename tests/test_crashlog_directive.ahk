#Requires AutoHotkey v2.1-alpha.29
; #CrashLog takes a literal path, resolved relative to CWD - run this from tests/.
#CrashLog tmp\directive.log
throw Error("directive test", "TestFn", "extra-info")
