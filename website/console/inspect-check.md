# Inspect & Check

Inspect answers **what is this value?** Check answers **can this source be parsed?** Neither answer substitutes for behavioral assertions.

::: info Check your build
`Inspect` is a demonstrated development feature. Confirm `--capabilities` before using this page's examples.
:::

## Describe a value without invoking its getters

```ahk
sample := ["alpha", 31, 2.5]
report := JSON.Parse(Inspect(sample))
Print("type={}, length={}", report["type"], report["length"])
```

`Inspect(value, depth := 2, maxItems := 100)` returns JSON. It reports properties and callable names, array items, map entries, and function information as applicable. Cycles and limits are represented rather than traversed indefinitely. It is designed not to invoke script getters while inspecting.

## Check source in a script

```ahk
good := Check("x := 1`nPrint(x)")
Print("valid={}", good.Ok)
bad := Check("x := `nif (")
Print("invalid={}, diagnostics={}", !bad.Ok, bad.Diagnostics.Length)
```

`Check` returns an object with `Ok` and `Diagnostics`. Check's temporary process/files are real; the function is not a pure in-memory proof of safety.

## Check a file through a tool

The CLI `check file.ahk` and native MCP `check` use the actual interpreter parser. A successful result says the source loads under that build. It does not prove a timer fires, a GUI button works, or an external application changes state.

Use inspection and source context to form a hypothesis, then encode the expected behavior in a test. The [demonstration fixture](/showcase) includes both valid and invalid Check inputs plus Inspect assertions.
