# tree-sitter-ahk.dll — AutoHotkey grammar for tree-sitter

`bin/tree-sitter-ahk.dll` is a self-contained x64 tree-sitter parser for AutoHotkey
source. It bundles the AHK grammar **and** a minimal slice of the tree-sitter runtime,
so scripts can use it directly via `DllCall` — no separate `tree-sitter.dll` required.

**Status:** vendored artifact, not yet wired into the engine. `AutoHotkey64.exe`
currently has no tree-sitter integration; this DLL is the building block for it.

## Exports (26)

| Group | Functions |
|---|---|
| Grammar entry | `tree_sitter_autohotkey` → `TSLanguage*` |
| Language | `ts_language_abi_version` (returns **15**, tree-sitter 0.25.x) |
| Parser | `ts_parser_new`, `ts_parser_delete`, `ts_parser_set_language`, `ts_parser_parse_string` |
| Tree | `ts_tree_root_node`, `ts_tree_delete` |
| Node | `ts_node_type`, `ts_node_symbol`, `ts_node_child`, `ts_node_child_count`, `ts_node_named_child`, `ts_node_named_child_count`, `ts_node_child_by_field_name`, `ts_node_field_name_for_child`, `ts_node_start_byte`, `ts_node_end_byte`, `ts_node_start_point`, `ts_node_end_point`, `ts_node_has_error`, `ts_node_is_error`, `ts_node_is_named`, `ts_node_is_missing`, `ts_node_is_extra`, `ts_node_is_null` |

## Calling convention gotcha: TSNode is a by-value struct

`TSNode` is 32 bytes (`uint32 context[4]; void* id; TSTree* tree`). On the x64
Windows ABI, by-value structs larger than 8 bytes are:

- **returned** through a hidden first pointer argument (sret), and
- **passed** as a pointer to a copy.

So from AHK, every `TSNode`-returning function takes a `Buffer(32)` as its first
`DllCall` argument, and every `TSNode`-taking function receives that buffer's pointer.

## Usage from AHK

```autohotkey
hMod := DllCall("LoadLibrary", "Str", A_ScriptDir "\bin\tree-sitter-ahk.dll", "Ptr")

lang   := DllCall("tree-sitter-ahk\tree_sitter_autohotkey", "Ptr")
parser := DllCall("tree-sitter-ahk\ts_parser_new", "Ptr")
DllCall("tree-sitter-ahk\ts_parser_set_language", "Ptr", parser, "Ptr", lang, "Char")

src := "x := 42`nMsgBox(x)`n"
buf := Buffer(StrPut(src, "UTF-8"))
len := StrPut(src, buf, "UTF-8") - 1
tree := DllCall("tree-sitter-ahk\ts_parser_parse_string",
    "Ptr", parser, "Ptr", 0, "Ptr", buf, "UInt", len, "Ptr")

root := Buffer(32)  ; TSNode out-param (sret)
DllCall("tree-sitter-ahk\ts_tree_root_node", "Ptr", root, "Ptr", tree, "Ptr")
Print("root: {}", DllCall("tree-sitter-ahk\ts_node_type", "Ptr", root, "AStr"))
; -> root: source_file

DllCall("tree-sitter-ahk\ts_tree_delete", "Ptr", tree)
DllCall("tree-sitter-ahk\ts_parser_delete", "Ptr", parser)
```

Top-level statements parse to named children of `source_file` — e.g.
`assignment_operation`, `function_call`.

## Smoke test

`tests/test_treesitter_dll.ahk` exercises the full surface: load, ABI check,
parse, child walk with byte ranges, and `has_error` on deliberately broken input.

```bash
bin/AutoHotkey64.exe tests/test_treesitter_dll.ahk   # prints PASS, exit 0
```
