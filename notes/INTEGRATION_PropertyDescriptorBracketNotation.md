# Integration Guide: Property Descriptors with Bracket Notation

## Integration into AHK_OOP Module System

This document provides integration guidance for the Property Descriptor Bracket Notation knowledge into the existing AutoHotkey v2 module system.

---

## Module Integration Points

### 1. Module_ClassPrototyping.md Enhancement

**Location to Add:** After section "Advanced Patterns" / Before "Creating New Classes at Runtime"

**New Section Title:** `BRACKET_NOTATION_WITH_PROPERTY_DESCRIPTORS`

**Content Summary:**
```markdown
## Bracket Notation with Property Descriptors

Property descriptors can leverage bracket notation to create flexible indexable properties.
AHK v2's parser routes bracket access based on getter parameter counts:

- **Single-parameter getters**: Bracket calls `__Item` on returned object
- **Multi-parameter getters**: Bracket passes arguments directly to getter

### The Routing Rule

The parser inspects the property getter's MinParams and MaxParams to determine routing:

```ahk
; Single-param: bracket calls __Item
MyProp {
    get {
        return Map()  ; Returns a Map; bracket accesses Map.__Item
    }
}

; Multi-param: bracket passes to getter
MyProp[Index?] {
    get(this, Index?) {
        ; Index parameter receives bracket argument
        return Index ?? "default"
    }
}
```

### Real-World Pattern: Parameterized Getters

The most powerful use case is creating properties that accept optional parameters:

```ahk
class RegExMatchData {
    _matches := []
    _lengths := []

    Len[N?] {
        get(this, N?) {
            if !IsSet(N)
                return this._matches.Length  ; Total count
            return this._lengths[N]          ; Specific length
        }
    }
}

data := RegExMatchData()
count := data.Len           ; Total matches
length := data.Len[1]       ; Length of match 1
```

### Critical Limitation: BoundFunc Parameter Inspection

BoundFunc objects do not expose MinParams/MaxParams, breaking parameter inspection:

```ahk
; FAILS - BoundFunc parameter inspection incomplete
DefineProp("Broken", {
    get: ((this, N?) => N).Bind(, "")
})

; WORKS - Explicit wrapper allows parameter detection
DefineProp("Fixed", {
    get: (this) => (N?) => N
})
```

See: GUIDE_PropertyDescriptorBracketNotation.md for complete details.
```

**Cross-Reference:** Add to existing "ANTI_PATTERNS" section:
```markdown
- Avoid using BoundFunc objects directly in property descriptors when bracket notation
  is needed; use explicit wrapper functions instead for proper parameter inspection
```

---

### 2. Module_DynamicProperties.md Enhancement

**Location to Add:** After "DYNAMIC_PROPERTIES" section / Before "META_FUNCTION_PATTERNS"

**New Subsection Title:** `BRACKET_NOTATION_PROPERTIES`

**Content Summary:**
```markdown
### Bracket Notation with Optional Parameters

For dynamic properties that support bracket notation parameter passing:

```ahk
class DynamicIndexed {
    _data := Map()

    Item[Key?] {
        get(this, Key?) {
            if !IsSet(Key)
                return this._data.Count
            return this._data.Get(Key, unset)
        }
    }
}
```

**Key Point:** The getter must have 2+ parameters for bracket arguments to be passed.
```

---

### 3. Module_Objects.md Enhancement

**Location to Add:** In "GET_SET_PATTERNS" section (TIER 2)

**Addition:**
```markdown
#### Multi-Parameter Property Getters (Bracket Notation)

For properties that need to accept optional parameters via bracket notation:

Reference: Module_ClassPrototyping.md "Bracket Notation with Property Descriptors"
and GUIDE_PropertyDescriptorBracketNotation.md for complete patterns.

Key pattern: `Property[Param?] { get(this, Param?) { ... } }`
```

---

## Reference Materials

### Comprehensive Guide
- **File:** `GUIDE_PropertyDescriptorBracketNotation.md`
- **Contains:** Full explanation, mechanics, real-world patterns, common mistakes
- **Use When:** Understanding the complete feature or debugging complex scenarios

### Quick Reference
- **File:** `GUIDE_PropertyDescriptorQuickReference.md`
- **Contains:** One-minute answer, decision trees, quick patterns, troubleshooting
- **Use When:** Quickly looking up syntax or common patterns

### Practical Examples
- **File:** `EXAMPLE_PropertyDescriptorBracketNotation.ahk`
- **Contains:** 10 working examples from basic to advanced
- **Use When:** Testing implementation or learning by example
- **Execution:** Run individual tests or use `RunAllTests()` function

---

## Detection System Integration

### Add to Module Detection System

**File:** Module detection trigger rules (in relevant module files)

**Explicit Triggers:**
- "bracket notation", "property[index]", "Len[N]", "parameterized getter"

**Implicit Triggers:**
- "access property with brackets" → Bracket notation with property descriptors
- "getter accepts parameters" → Multi-parameter property pattern
- "BoundFunc in DefineProp fails" → BoundFunc parameter inspection limitation

---

## Agent Pipeline Integration

### For /ahk-orchestrator Pipeline

**Designer Agent** would identify:
- User requests "create indexable property" or "property that accepts parameters"
- Need for bracket notation support
- Pattern matches RegExMatchInfo or similar built-in behavior

**Context Agent** would synthesize:
- Multi-parameter getter pattern from Module_ClassPrototyping.md
- Parameter count routing rules from this guide
- BoundFunc workaround if needed

**Coding Agent** would implement:
- Using proper `Property[Param?] { get(this, Param?) { ... } }` syntax
- Error handling for optional parameters
- Validation of index/parameters in getter body

---

## Code Quality Checklist

When implementing property descriptors with bracket notation:

- [ ] Getter has 2+ parameters for bracket access to work
- [ ] Use optional parameters: `Property[N?]` not `Property[N]`
- [ ] Handle `IsSet()` checks for optional parameters
- [ ] Provide validation/bounds checking in getter
- [ ] Document expected bracket arguments in comments
- [ ] Avoid BoundFunc; use explicit wrappers if needed
- [ ] Test both bracket and non-bracket access paths

---

## Performance Implications

- **Parameter inspection:** Happens at parse/definition time, not runtime
- **Overhead:** Zero for multi-parameter getters vs single-parameter getters
- **Exception:** BoundFunc inspection requires workaround (slight overhead)

---

## Migration Guide

### From Single-Parameter to Multi-Parameter

**Before (bracket acts on returned value):**
```ahk
Data {
    get {
        return Map(1, "A", 2, "B")  ; Bracket accesses Map.__Item
    }
}

value := obj.Data[1]  ; "A" from Map
```

**After (bracket passes to getter):**
```ahk
Data[N?] {
    get(this, N?) {
        if !IsSet(N)
            return "All data"
        return this._map[N]  ; Now can customize behavior
    }
}

value := obj.Data[1]  ; Reaches getter with N=1
```

---

## Testing Patterns

### Verification Test
```ahk
TestPropertyDescriptor() {
    class TestProp {
        Prop[N?] {
            get(this, N?) {
                return IsSet(N) ? N : "none"
            }
        }
    }

    obj := TestProp()
    assert(obj.Prop = "none", "No bracket should return default")
    assert(obj.Prop[5] = 5, "Bracket should pass parameter to getter")
}
```

---

## Related Concepts

### In This Project
- Module_ClassPrototyping.md - Property descriptor fundamentals
- Module_Objects.md - Object property patterns
- Module_DynamicProperties.md - Dynamic property creation

### In AutoHotkey v2
- `DefineProp()` function
- Property descriptors (get/set/call)
- Meta-functions (__Get, __Set)
- Optional parameters

---

## Troubleshooting Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Bracket not reaching getter | Single-param getter | Add optional parameter: `Prop[N?]` |
| "Too many parameters" error | BoundFunc used directly | Wrap with explicit function |
| Bracket acts on returned Map | Single-param returning Map | Use multi-param getter |
| Parameter always unset | Accessing without bracket | Add bracket: `obj.Prop[value]` |
| Works in one context, not another | Parser interpretation varies | Check if bracket is syntactically valid |

---

## Examples in This Project

Ready-to-run examples in `EXAMPLE_PropertyDescriptorBracketNotation.ahk`:

1. Basic bracket parameter passing
2. Array-like property access
3. RegExMatchInfo-style implementation
4. Configuration access pattern
5. Multi-dimensional array access
6. Counter with indexed access
7. BoundFunc pitfall and workaround
8. Versioned data access
9. Parameter validation in getter
10. Single vs multi-parameter comparison

Each example includes test function for immediate verification.

---

## Additional Resources

- **AutoHotkey v2 Docs:** https://www.autohotkey.com
- **Property Descriptors:** https://www.autohotkey.com/docs/v2/misc/Classes.htm#DefineProp
- **Built-in Examples:** RegExMatchInfo.Len, RegExMatchInfo.Pos

---

## Summary

Property descriptors with bracket notation are a powerful but underutilized feature in AHK v2. The key insight is:

**Multi-parameter getters enable bracket notation to pass arguments directly to the getter, not call `__Item` on the returned value.**

This pattern is used in AHK v2 built-ins like RegExMatchInfo and can be leveraged for sophisticated APIs in user code.

For comprehensive understanding, see:
- Full guide: GUIDE_PropertyDescriptorBracketNotation.md
- Quick ref: GUIDE_PropertyDescriptorQuickReference.md
- Examples: EXAMPLE_PropertyDescriptorBracketNotation.ahk
