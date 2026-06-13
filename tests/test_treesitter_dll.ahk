/*
test_treesitter_dll.ahk — smoke test for bin\tree-sitter-ahk.dll

Verifies the self-contained grammar DLL end-to-end via DllCall:
load, language handle, ABI version, parse a snippet, walk the root
node's children, and confirm error detection on broken source.

TSNode is a 32-byte by-value struct (uint32 context[4]; void* id; TSTree* tree).
On x64 Windows ABI, by-value structs >8 bytes are returned through a hidden
first pointer arg (sret) and passed as a pointer to a copy — hence the
Buffer(32) dance below.
*/
#Requires AutoHotkey v2.1-alpha.30

DLL := A_ScriptDir "\..\bin\tree-sitter-ahk.dll"

Fail(msg) {
    Print("FAIL: {}", msg)
    ExitApp(1)
}

hMod := DllCall("LoadLibrary", "Str", DLL, "Ptr")
if (!hMod)
    Fail("LoadLibrary returned 0 for " DLL)

lang := DllCall("tree-sitter-ahk\tree_sitter_autohotkey", "Ptr")
if (!lang)
    Fail("tree_sitter_autohotkey() returned null")

abi := DllCall("tree-sitter-ahk\ts_language_abi_version", "Ptr", lang, "UInt")
Print("language ok, ABI version {}", abi)

parser := DllCall("tree-sitter-ahk\ts_parser_new", "Ptr")
if (!DllCall("tree-sitter-ahk\ts_parser_set_language", "Ptr", parser, "Ptr", lang, "Char"))
    Fail("ts_parser_set_language rejected the language (ABI mismatch?)")

ParseSource(src) {
    buf := Buffer(StrPut(src, "UTF-8"))
    len := StrPut(src, buf, "UTF-8") - 1
    return DllCall("tree-sitter-ahk\ts_parser_parse_string",
        "Ptr", parser, "Ptr", 0, "Ptr", buf, "UInt", len, "Ptr")
}

; --- valid source ---
tree := ParseSource("x := 42`nMsgBox(x)`n")
if (!tree)
    Fail("ts_parser_parse_string returned null tree")

root := Buffer(32)
DllCall("tree-sitter-ahk\ts_tree_root_node", "Ptr", root, "Ptr", tree, "Ptr")

rootType := DllCall("tree-sitter-ahk\ts_node_type", "Ptr", root, "AStr")
hasError := DllCall("tree-sitter-ahk\ts_node_has_error", "Ptr", root, "Char")
count := DllCall("tree-sitter-ahk\ts_node_named_child_count", "Ptr", root, "UInt")
Print("root: '{}', named children: {}, has_error: {}", rootType, count, hasError)

if (hasError)
    Fail("valid source reported has_error=1")
if (count < 2)
    Fail("expected >=2 top-level statements, got " count)

child := Buffer(32)
loop count {
    DllCall("tree-sitter-ahk\ts_node_named_child", "Ptr", child, "Ptr", root, "UInt", A_Index - 1, "Ptr")
    cType := DllCall("tree-sitter-ahk\ts_node_type", "Ptr", child, "AStr")
    cStart := DllCall("tree-sitter-ahk\ts_node_start_byte", "Ptr", child, "UInt")
    cEnd := DllCall("tree-sitter-ahk\ts_node_end_byte", "Ptr", child, "UInt")
    Print("  child {}: '{}' [{}..{}]", A_Index, cType, cStart, cEnd)
}
DllCall("tree-sitter-ahk\ts_tree_delete", "Ptr", tree)

; --- broken source must flag an error ---
badTree := ParseSource("if (((`n")
DllCall("tree-sitter-ahk\ts_tree_root_node", "Ptr", root, "Ptr", badTree, "Ptr")
badError := DllCall("tree-sitter-ahk\ts_node_has_error", "Ptr", root, "Char")
Print("broken source has_error: {}", badError)
DllCall("tree-sitter-ahk\ts_tree_delete", "Ptr", badTree)
if (!badError)
    Fail("broken source not flagged by has_error")

DllCall("tree-sitter-ahk\ts_parser_delete", "Ptr", parser)
Print("PASS")
ExitApp(0)
