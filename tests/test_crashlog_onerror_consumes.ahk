; Requires AutoHotkey v2.1-alpha.29 (run with the custom build)
; OnError handler returns 1 (consume) - [ERROR] must NOT be logged.
OnError((e, mode) => 1)
throw TypeError("This should NOT be logged", "TestFn", "test-extra")
ExitApp 0
