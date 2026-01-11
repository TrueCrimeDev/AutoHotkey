#Requires AutoHotkey v2.0
#Include DebugClient.ahk

; Wait a bit for server to be ready
Sleep(2000)

; Trigger an error
try {
    throw Error("Test Agent Stream Error", -1, "This is a test error for the agent stream")
} catch as err {
    ; The DebugClient hooks into OnError, but since we caught it here, 
    ; we need to manually trigger it or let it go unhandled.
    ; Actually DebugClient hooks OnError, which catches UNHANDLED errors.
    ; So we should just throw and let it bubble up.
}

; Throw an unhandled error
throw Error("Unhandled Test Error", -1, "Agent Stream Verification")
