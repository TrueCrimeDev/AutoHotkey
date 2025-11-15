#Requires AutoHotkey v2.1-alpha.17
#SingleInstance Force

Import ArrayHelpers
Import { Join as JoinArray, Split as SplitInto } from ArrayHelpers

ArrayHelpers.EnsureArrayHelpers()

values := ["one", "two", "three"]
MsgBox ArrayHelpers.Join(values, " - ")
MsgBox JoinArray(values, " | ")

bucket := []
SplitInto("alpha,beta,gamma", ",", bucket)
MsgBox bucket.Join(" · ")
