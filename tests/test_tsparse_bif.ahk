/*
test_tsparse_bif.ahk — smoke test for the native TSParse() BIF

Exercises the engine-level tree-sitter integration (source/error.cpp +
source/lib/functions.h) end to end: parse, tree wrapper, node fields, child
walk, named-child filtering, node text, and error detection.

REQUIRES a from-source rebuild (build_local.bat) — TSParse does not exist in
engine builds that predate the integration; those raise
"Error: TSParse — call to nonexistent function".
*/
#Requires AutoHotkey v2.1-alpha.30

Fail(msg) {
    Print("FAIL: {}", msg)
    ExitApp(1)
}

; Note: on engines without the TSParse BIF, `TSParse(...)` parses as a dynamic
; call through an (unset) variable and errors at runtime with "this global
; variable has not been assigned a value". After the rebuild it resolves to the
; built-in. There is no useful runtime guard for its absence.

; --- valid source ---
tree := TSParse("x := 42`nMsgBox(x)`n")
if (tree.Root.Type != "source_file")
    Fail("root type '" tree.Root.Type "' != source_file")
if (tree.HasError)
    Fail("valid source reported HasError=1")

root := tree.Root
Print("root: '{}', children: {}, named: {}, hasError: {}",
    root.Type, root.Children.Length, root.NamedChildren.Length, tree.HasError)

if (root.NamedChildren.Length < 2)
    Fail("expected >=2 named children, got " root.NamedChildren.Length)

stmt1 := root.NamedChildren[1]
stmt2 := root.NamedChildren[2]
if (stmt1.Type != "assignment_operation")
    Fail("child 1 type '" stmt1.Type "' != assignment_operation")
if (stmt2.Type != "function_call")
    Fail("child 2 type '" stmt2.Type "' != function_call")

for node in root.NamedChildren
    Print("  {} [{}..{}] r{}c{}  text={}",
        node.Type, node.StartByte, node.EndByte, node.StartRow, node.StartCol, node.Text)

; node text must round-trip the source slice
if (stmt1.Text != "x := 42")
    Fail("stmt1.Text '" stmt1.Text "' != 'x := 42'")

; --- broken source must flag an error ---
bad := TSParse("if (((`n")
Print("broken source HasError: {}", bad.HasError)
if (!bad.HasError)
    Fail("broken source not flagged by HasError")

Print("PASS")
ExitApp(0)
