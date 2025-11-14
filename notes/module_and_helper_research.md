# Module and Helper Research

## Module definition patterns
- Built-in functions are registered through `MdFuncEntry` records populated by including `source/lib/functions.h` twice with different `md_mode` values. The table is binary-searched in `Script::GetBuiltInMdFunc`, which instantiates `MdFunc` wrappers that understand argument metadata and dispatch to native implementations. 【F:source/MdFunc.cpp†L19-L60】
- `source/lib/functions.h` groups script-visible names in PascalCase, reusing macros such as `md_func`, `md_func_v`, and shared argument packs like `MD_CONTROL_ARGS`. This keeps metadata declarative and mirrors the command naming that appears in `source/lib/*.cpp`. 【F:source/lib/functions.h†L2-L120】
- Script modules created with `#Module` follow `ScriptModule`'s bookkeeping: directives allocate a new `ScriptModule`, inherit warning settings, and register imports via `ParseImportStatement`/`ResolveImports`. Exports are enforced through `ScriptModule::Invoke`, which only exposes explicitly exported vars. 【F:source/script_module.cpp†L9-L200】

## Existing helpers worth reusing

### Core string utilities
- `source/util.h` already defines inline helpers for character classification, casing, and whitespace trimming (`StrChrAny`, `omit_leading_whitespace`, `omit_trailing_whitespace`, etc.), plus cross-platform `tmem*` macros. These should be reused rather than reimplemented. 【F:source/util.h†L31-L198】
- `source/util.cpp` extends the same module with higher-level date/time string helpers such as `GetISOWeekNumber`, `YYYYMMDDToFileTime`, and parsers that translate AutoHotkey time formats into `SYSTEMTIME`. Leveraging these avoids duplicating locale-sensitive parsing. 【F:source/util.cpp†L24-L200】
- `source/StringConv.h` exposes encoding conversions between ANSI, UTF-8, and wide strings and supplies convenience wrappers (`CStringWCharFromUTF8`, `CStringCharFromWChar`, etc.). Any new UTF-aware helpers should call into these adapters for consistency. 【F:source/StringConv.h†L5-L146】
- `source/KuString.h` provides the copy-on-write `CKuStringT` family plus locale-aware utilities (case-insensitive comparisons, span helpers). When a mutable `CString`-like type is needed, this header is the canonical option instead of bespoke classes. 【F:source/KuString.h†L21-L200】

### Array and collection support
- The built-in `Array` type already encapsulates capacity management, mutation helpers (`InsertAt`, `RemoveAt`, `Append` overloads), enumeration, cloning, and parameter packing utilities. Future collection helpers should extend this class rather than introduce parallel array abstractions. 【F:source/script_object.h†L654-L717】

## Naming guidance for upcoming utilities
- New script-callable helpers should keep using PascalCase names in `source/lib/functions.h`, grouped with related commands (e.g., string-focused helpers next to existing `String` entries) and implemented in the corresponding `source/lib/<area>.cpp` file such as `string.cpp` for textual operations or `vars.cpp` for variable utilities. 【F:source/lib/functions.h†L2-L120】
- Internal helper code that is not script-visible fits best in the existing `util` module alongside the inline helpers and parsers (`util.h`/`util.cpp`). Stick with free functions in the global scope or file-static helpers, matching the current style that avoids explicit namespaces. 【F:source/util.h†L31-L198】【F:source/util.cpp†L24-L200】
- Array-related enhancements should live with the `Array` class in `script_object.{h,cpp}` so that metadata (`Array::sMembers`) and behavior stay centralized. Maintain the existing `Array` method naming (PascalCase verbs like `InsertAt`, `Clone`) to remain coherent with exposed methods. 【F:source/script_object.h†L654-L717】

## Reference module scripts for import testing
- `scripts/v2/StringHelpers.ahk` is a standalone module that declares `#Module StringHelpers` and exports `CollapseWhitespace` and `ToTitleCase`. Keep reusable AutoHotkey v2 helpers in this folder so they can be exercised without rebuilding the engine; engine-level helpers that should ship with AutoHotkey belong in `source/lib/string.cpp` and are registered through `source/lib/functions.h` as noted above.
- `scripts/v2/ArrayHelpers.ahk` declares `#Module ArrayHelpers`, exports `Join`, `Split`, and `EnsureArrayHelpers`, and registers the same helpers on `Array.Prototype` the first time it executes. Importing the module object yields read-only bindings (`Import ArrayHelpers`) while selective imports can bind individual helpers directly.
- A caller can either import the module object for Strings or Arrays (for example, `Import StringHelpers as Strings`, `Import ArrayHelpers as Arrays`) and invoke exports as members, or selectively import individual helpers (`Import { CollapseWhitespace } from StringHelpers`, `Import { Join } from ArrayHelpers`). Both approaches are equivalent because exports become read-only bindings in the importing module.
- `scripts/v2/tests/ImportStringHelpersExample.ahk` demonstrates importing both modules, invoking String helpers, calling Array helpers through the module object, and exercising the prototype extensions installed by `ArrayHelpers`.

