# tree-sitter-ahk.dll — AutoHotkey grammar for tree-sitter

`bin/tree-sitter-ahk.dll` is a self-contained x64 tree-sitter parser for AutoHotkey
source. It bundles the AHK grammar **and** a minimal slice of the tree-sitter runtime,
so scripts can use it directly via `DllCall` — no separate `tree-sitter.dll` required.

**Status:** the engine exposes a native **`TSParse()`** BIF (see below) that wraps
this DLL — no `DllCall` needed. The raw `DllCall` surface documented further down
still works and is the fallback on builds that predate the BIF.

> `TSParse()` requires the engine to be rebuilt from source (`build_local.bat`).
> Stock `AutoHotkey64.exe` builds before that rebuild will raise
> `Error: TSParse — call to nonexistent function`.

## Native API: `TSParse(Source)`

`TSParse(source)` loads `tree-sitter-ahk.dll` on first use (preferring the copy
next to the executable, then the normal DLL search path), parses `source`, walks
the entire tree in C++, and returns a snapshot of plain AHK objects. The native
`TSTree` is freed before `TSParse` returns, so there are no native handles to
release and nothing to leak.

```autohotkey
tree := TSParse("x := 42`nMsgBox(x)")
Print("root: {}, hasError: {}", tree.Root.Type, tree.HasError)   ; source_file, 0
for node in tree.Root.Children
    Print("  {} [{}..{}]  {}", node.Type, node.StartByte, node.EndByte, node.Text)
```

Returned tree object:

| Prop | Meaning |
|---|---|
| `Root` | root node object (see below) |
| `Source` | the original source string (UTF-16, as passed) |
| `HasError` | `1` if the parse tree contains any error/missing nodes, else `0`. Structure-only — not a validity check. The grammar is incomplete for this fork and reports `HasError=1` on valid code (typed Structs, fat-arrow methods, `^j::` hotkeys). To test whether source actually parses, use the `Check(Source)` BIF (real-engine oracle) or the `check` CLI subcommand. |

Each node object:

| Prop | Type | Meaning |
|---|---|---|
| `Type` | String | grammar symbol, e.g. `assignment_operation`, `function_call` |
| `StartByte` / `EndByte` | Int | UTF-8 byte offsets into the source |
| `StartRow` / `StartCol` | Int | 0-based row, **UTF-8 byte** column of the start |
| `EndRow` / `EndCol` | Int | 0-based row / byte column of the end |
| `Text` | String | the node's source slice, re-decoded to UTF-16 |
| `IsNamed` / `IsMissing` / `IsError` / `IsExtra` | Int | node-kind flags (0/1) |
| `HasError` | Int | 1 if this node or any descendant is an error/missing node |
| `FieldName` | String | this node's field name in its parent, or `""` |
| `Children` | Array | all children (named + anonymous) |
| `NamedChildren` | Array | named children only |
| `Truncated` | Int | 1 if children were omitted at the depth cap (1000), else 0 |

Errors are raised as exceptions: a missing/invalid DLL throws
`tree-sitter-ahk.dll could not be loaded …`; a runtime/grammar ABI mismatch
throws `tree-sitter language/runtime ABI mismatch.`

Implementation: `source/error.cpp` (next to `_ScriptGetLines`), registered in
`source/lib/functions.h`.

## Validity: Check(Source)

`TSParse().HasError` is not a validity signal. Use the native `Check(Source)` BIF — it spawns this exe in check mode against a temp file in a child process (oracle-parity with the CLI, host state untouched). The child runs validate-then-exit mode (parses but never executes), so a Check() inside the source cannot recurse. Returns `Ok` (1 valid / 0 invalid), `Diagnostics` (Array, empty when Ok=1, items `{Severity,Type,Code,Message,Extra,File,Line,Column}`), and `Raw`. On spawn failure returns Ok=0 with a synthetic diagnostic (no throw).

## Raw `DllCall` surface

The DLL is also a plain tree-sitter parser usable directly — useful on stock
builds, or for incremental parsing / queries the snapshot API doesn't expose.

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
