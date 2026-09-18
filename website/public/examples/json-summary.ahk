#Requires AutoHotkey v2.1-alpha.31
if A_Args.Length != 1
    throw ValueError("Expected one JSON argument")
config := JSON.Parse(A_Args[1])
result := {name: config["name"], doubled: config["count"] * 2}
Print(JSON.Stringify(result))
