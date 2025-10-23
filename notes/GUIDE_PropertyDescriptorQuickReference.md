# Property Descriptor Bracket Notation - Quick Reference

## One-Minute Answer

```ahk
; Want: obj.property[index] where index reaches the getter
; Solution: Multi-parameter getter with optional params

Property[Index?] {
    get(this, Index?) {
        if !IsSet(Index)
            return "no index"
        return "got: " Index
    }
}
```

## Parameter Count Decision Tree

```
obj.property[index]
    ↓
Does getter have 1 parameter (this only)?
    ├─ YES → Bracket calls __Item on returned object
    └─ NO (2+ parameters) → Bracket passes index to getter
```

## Quick Patterns

### Pattern A: Optional Index Access
```ahk
Data[N?] {
    get(this, N?) {
        if !IsSet(N)
            return "all"
        return N
    }
}

obj.Data       ; "all"
obj.Data[5]    ; 5
```

### Pattern B: Map-Based Indexing
```ahk
Items[Key?] {
    get(this, Key?) {
        if !IsSet(Key)
            return this._map.Count
        return this._map.Get(Key, unset)
    }
}
```

### Pattern C: Multi-Parameter Indexing
```ahk
Cell[Row?, Col?] {
    get(this, Row?, Col?) {
        if !IsSet(Row) || !IsSet(Col)
            return "needs 2 params"
        return this._data[Row][Col]
    }
}

obj.Cell[1, 2]  ; Row 1, Col 2
```

## Do's and Don'ts

### ✓ DO This
```ahk
; Multi-param getter for bracket access
MyProp[N?] {
    get(this, N?) {
        return N ?? "default"
    }
}
```

### ✗ DON'T Do This
```ahk
; Single-param getter (brackets won't reach here)
MyProp {
    get {
        return Map()
    }
}

; BoundFunc (parameter inspection fails)
MyProp {
    get: ((this, N?) => N).Bind(, "")
}
```

### ✓ WORKAROUND for BoundFunc
```ahk
; Wrap to avoid BoundFunc
MyProp {
    get: (this) => (N?) => N
}

obj.MyProp()[5]  ; Works
```

## Common Syntax Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Too many parameters` | BoundFunc in descriptor | Wrap with explicit function |
| Bracket not reaching getter | Single-param getter | Add optional parameter |
| `Not enough parameters` | Required param in bracket | Make it optional with `?` |
| Bracket acts on Map | Single getter returning Map | Use multi-param getter |

## Real-World Examples

### RegExMatchInfo Style
```ahk
Len[N?] {
    get(this, N?) {
        if !IsSet(N)
            return this._all.Length
        return StrLen(this._all[N])
    }
}

match.Len        ; Total
match.Len[1]     ; First group length
```

### Configuration Access
```ahk
Config[Path?] {
    get(this, Path?) {
        if !IsSet(Path)
            return this._map.Clone()
        return this._map[Path]
    }
}

cfg.Config                     ; All config
cfg.Config["database.host"]    ; Specific value
```

### Array-Like Access
```ahk
Item[Index?] {
    get(this, Index?) {
        if !IsSet(Index)
            return this._items.Length
        return this._items[Index]
    }
}

obj.Item       ; Count
obj.Item[3]    ; Third item
```

## Testing Bracket Access

```ahk
; Verify getter receives parameters
class Test {
    Prop[N?] {
        get(this, N?) {
            return IsSet(N) ? "got " N : "none"
        }
    }
}

t := Test()
MsgBox t.Prop         ; "none"
MsgBox t.Prop[5]      ; "got 5"
```

## Integration with AHK Modules

Add to `Module_ClassPrototyping.md`:
```
## Bracket Notation with Property Descriptors

Multi-parameter getters enable bracket notation to pass arguments
directly to the getter (not call __Item on returned value).

Key pattern: `Property[Param?] { get(this, Param?) { ... } }`

For advanced patterns, see GUIDE_PropertyDescriptorBracketNotation.md
```

## Troubleshooting

**Q: Bracket not reaching getter?**
A: Check getter parameter count. Single-param getters route brackets to `__Item`.

**Q: BoundFunc doesn't work?**
A: Wrap with explicit function wrapper to expose parameter count.

**Q: Multiple bracket parameters?**
A: Use `Prop[A?, B?, C?] { get(this, A?, B?, C?) { ... } }`

**Q: Want bracket and parentheses?**
A: Use setter for assignment: `Property[N] { set { ... } }`

## Performance Notes

- Parameter inspection happens at parse time, not runtime
- Zero overhead for multi-param getters vs single-param
- BoundFunc inspection is the exception (requires workaround)

## Related Resources

- Full guide: `GUIDE_PropertyDescriptorBracketNotation.md`
- Module: `Module_ClassPrototyping.md`
- Discord discussion source: Advanced property descriptor patterns
