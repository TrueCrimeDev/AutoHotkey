; Requires AutoHotkey v2.1-alpha.29 (run with the custom build)
; No OnError handler - error propagates - [ERROR] must be logged.
throw TypeError("Test message", "TestFn", "test-extra")
