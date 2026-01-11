#Requires AutoHotkey v2.0

; Test script that generates an error for the Error Agent to capture

; Create a user object without email property
user := {
    name: "John Doe",
    id: 123,
    role: "Developer"
}

; Function that tries to access missing property
ProcessUser(userData) {
    local result := ""

    ; These work fine
    name := userData.name
    id := userData.id

    ; This will throw an error - no "email" property!
    email := userData.email

    result := name . " (" . email . ")"
    return result
}

; Main execution
Main() {
    global user

    MsgBox("Starting user processing...")

    ; This call will fail
    output := ProcessUser(user)

    MsgBox("Result: " . output)
}

; Run main
Main()
