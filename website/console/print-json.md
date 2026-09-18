# Print & native JSON

These APIs make AHK scripts convenient producers and consumers of structured data. They are built into the Console fork; no JSON library include is needed.

## Print rules

```ahk
Print()
Print("Literal {braces}")
Print("count={}, hex=0x{:X}", 42, 42)
```

`Print()` writes a blank line. One argument is literal. With additional arguments, the first argument is a `Format` template. Output is UTF-8 with a newline. You do not need `Print(Format(...))`.

## Parse, update, serialize

```ahk
#Requires AutoHotkey v2.1-alpha.31
config := JSON.Parse('{"name":"demo","enabled":true,"count":3}')
config["count"] += 1
Print(JSON.Stringify(config))
```

Parsed objects use the fork's ordered `JSON.Object`; bracket indexing works for property names. Parsed boolean/null values have compatibility behavior: by default script reads see `1`, `0`, and `""`, while original JSON tags preserve untouched round trips.

## Preserve explicit JSON types

```ahk
values := JSON.Parse('[true,false,null]', {Booleans: "native", Null: "native"})
Print(JSON.Stringify(values))
values[1] := JSON.False
Print(JSON.Stringify(values))
```

Assign `JSON.True`, `JSON.False`, or `JSON.Null` when the serialized type matters. Assignment replaces an element's original type tag. The parser rejects object keys containing NUL to avoid truncation/collision; string values can contain embedded NUL.

## Keep JSONL useful

Write one JSON object per line to stdout and send progress text to stderr:

```ahk
FileAppend("processing`n", "**")
Print(JSON.Stringify({status: "ready", count: 4}))
```

Mixed human text and JSON on the same stream can break downstream consumers. The demo's [raw dry-run checker issue](/clautohotkey/harness#stdout-and-result-records) is a concrete example.

Try the complete [JSON command-line recipe](/recipes/json-cli).
