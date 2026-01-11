; Using a Controller as a Mouse
; https://www.autohotkey.com
; This script converts a controller (gamepad, joystick, etc.) into a three-button
; mouse. It allows each button to drag just like a mouse button and it uses
; virtually no CPU time. Also, it will move the cursor faster depending on how far
; you push the stick from center. You can personalize various settings at the
; top of the script.
;
; Note: For Xbox controller 2013 and newer (anything newer than the Xbox 360
; controller), this script will only work if a window it owns is active,
; such as a message box, GUI, or the script's main window.

ContMultiplier := 0.30
ContThreshold := 3
InvertYAxis := false
ButtonLeft := 1
ButtonRight := 2
ButtonMiddle := 3
WheelDelay := 250
ControllerNumber := 1

#SingleInstance

ControllerPrefix := ControllerNumber "Joy"
Hotkey ControllerPrefix . ButtonLeft, ClickButtonLeft
Hotkey ControllerPrefix . ButtonRight, ClickButtonRight
Hotkey ControllerPrefix . ButtonMiddle, ClickButtonMiddle

ContThresholdUpper := 50 + ContThreshold
ContThresholdLower := 50 - ContThreshold
if InvertYAxis
    YAxisMultiplier := -1
else
    YAxisMultiplier := 1

SetTimer WatchController, 10

JoyInfo := GetKeyState(ControllerNumber "JoyInfo")
if InStr(JoyInfo, "P")
    SetTimer MouseWheel, WheelDelay

ClickButtonLeft(*)
{
    SetMouseDelay -1
    MouseClick "Left",,, 1, 0, "D"
    SetTimer WaitForLeftButtonUp, 10

    WaitForLeftButtonUp()
    {
        if GetKeyState(A_ThisHotkey)
            return
        SetTimer , 0
        SetMouseDelay -1
        MouseClick "Left",,, 1, 0, "U"
    }
}

ClickButtonRight(*)
{
    SetMouseDelay -1
    MouseClick "Right",,, 1, 0, "D"
    SetTimer WaitForRightButtonUp, 10

    WaitForRightButtonUp()
    {
        if GetKeyState(A_ThisHotkey)
            return
        SetTimer , 0
        MouseClick "Right",,, 1, 0, "U"
    }
}

ClickButtonMiddle(*)
{
    SetMouseDelay -1
    MouseClick "Middle",,, 1, 0, "D"
    SetTimer WaitForMiddleButtonUp, 10

    WaitForMiddleButtonUp()
    {
        if GetKeyState(A_ThisHotkey)
            return
        SetTimer , 0
        MouseClick "Middle",,, 1, 0, "U"
    }
}

WatchController()
{
    global
    MouseNeedsToBeMoved := false
    JoyX := GetKeyState(ControllerNumber "JoyX")
    JoyY := GetKeyState(ControllerNumber "JoyY")
    if JoyX > ContThresholdUpper
    {
        MouseNeedsToBeMoved := true
        DeltaX := Round(JoyX - ContThresholdUpper)
    }
    else if JoyX < ContThresholdLower
    {
        MouseNeedsToBeMoved := true
        DeltaX := Round(JoyX - ContThresholdLower)
    }
    else
        DeltaX := 0
    if JoyY > ContThresholdUpper
    {
        MouseNeedsToBeMoved := true
        DeltaY := Round(JoyY - ContThresholdUpper)
    }
    else if JoyY < ContThresholdLower
    {
        MouseNeedsToBeMoved := true
        DeltaY := Round(JoyY - ContThresholdLower)
    }
    else
        DeltaY := 0
    if MouseNeedsToBeMoved
    {
        SetMouseDelay -1
        MouseMove DeltaX * ContMultiplier, DeltaY * ContMultiplier * YAxisMultiplier, 0, "R"
    }
}

MouseWheel()
{
    global
    JoyPOV := GetKeyState(ControllerNumber "JoyPOV")
    if JoyPOV = -1
        return
    if (JoyPOV > 31500 or JoyPOV < 4500)
        Send "{WheelUp}"
    else if JoyPOV >= 13500 and JoyPOV <= 22500
        Send "{WheelDown}"
}
