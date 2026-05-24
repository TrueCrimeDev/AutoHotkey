F1::
{
    x := 1
    y := 2
    z := x + y
    ToolTip "Sum is " z
    SetTimer () => ToolTip(), -2000
}

F2::
{
    Loop 5
        A_Clipboard := "iteration " A_Index
}

Esc::ExitApp
Persistent
