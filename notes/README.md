# AutoHotkey v2 Notes

This folder contains comprehensive guides, examples, and integration documentation for advanced AutoHotkey v2 features.

## Property Descriptor Bracket Notation

A complete resource explaining how property descriptors with bracket notation work in AutoHotkey v2, answering the question: **"How can I create a property descriptor that accepts optional parameters through bracket notation?"**

### Files in This Collection

#### 1. **GUIDE_PropertyDescriptorBracketNotation.md**
The comprehensive guide covering all aspects of this feature:
- The mystery and discovery of how bracket notation routing works
- The mechanical rules AHK v2 uses to route bracket access
- The BoundFunc parameter inspection pitfall and workarounds
- Complete solution patterns with real-world examples
- Common mistakes and how to avoid them
- Testing and validation approaches

**Best for:** Understanding the complete feature deeply or debugging complex scenarios

**Length:** ~15 KB | **Read time:** 15-20 minutes

---

#### 2. **GUIDE_PropertyDescriptorQuickReference.md**
Quick reference guide with syntax and patterns:
- One-minute answer to the core question
- Parameter count decision tree
- Quick patterns (3 common implementations)
- Do's and Don'ts summary
- Common syntax errors table
- Real-world examples (RegExMatchInfo, Config, Array)
- Troubleshooting FAQ

**Best for:** Quick lookup when you remember the concept but need syntax

**Length:** ~4.5 KB | **Read time:** 5 minutes

---

#### 3. **EXAMPLE_PropertyDescriptorBracketNotation.ahk**
Runnable AutoHotkey v2 code with 10 working examples:

1. Basic bracket parameter passing
2. Array-like property access
3. RegExMatchInfo-style implementation
4. Configuration access pattern
5. Multi-dimensional array (matrix) access
6. Counter with indexed access
7. BoundFunc pitfall and workaround
8. Versioned data access
9. Parameter validation in getter
10. Single vs multi-parameter comparison

**Best for:** Learning by example or testing implementations

**How to use:**
- Run `RunAllTests()` to see all examples
- Run individual test functions like `TestBasic()`, `TestMatrix()`, etc.
- Copy patterns into your own code

**Length:** ~12 KB | **Execution time:** <1 minute per test

---

#### 4. **INTEGRATION_PropertyDescriptorBracketNotation.md**
Integration guide for the AHK_OOP module system:
- Specific locations to add content to Module_ClassPrototyping.md
- Enhancement suggestions for Module_DynamicProperties.md
- Cross-references for Module_Objects.md
- Detection system integration (explicit/implicit triggers)
- Agent pipeline integration for /ahk-orchestrator
- Code quality checklist
- Migration guide from single to multi-parameter patterns
- Troubleshooting table

**Best for:** Project maintainers integrating this knowledge into the module system

**Length:** ~9.7 KB

---

## Quick Start

### If you have 1 minute:
Read: **GUIDE_PropertyDescriptorQuickReference.md**

### If you have 5 minutes:
1. Read: **GUIDE_PropertyDescriptorQuickReference.md** (one-minute answer)
2. Look at: **EXAMPLE_PropertyDescriptorBracketNotation.ahk** (Example 1-2)

### If you have 15 minutes:
1. Read: **GUIDE_PropertyDescriptorBracketNotation.md** (full guide)
2. Run: **EXAMPLE_PropertyDescriptorBracketNotation.ahk** (1-3 examples)

### If you're integrating into modules:
1. Read: **INTEGRATION_PropertyDescriptorBracketNotation.md**
2. Reference: **GUIDE_PropertyDescriptorBracketNotation.md** (Mechanics section)
3. Copy patterns from: **EXAMPLE_PropertyDescriptorBracketNotation.ahk**

---

## The Core Concept

**Multi-parameter getters enable bracket notation to pass arguments directly to the getter, not call `__Item` on the returned value.**

```ahk
; Single-param: bracket calls __Item on returned object
MyProp {
    get {
        return Map()  ; Bracket acts on Map
    }
}

; Multi-param: bracket passes to getter
MyProp[Index?] {
    get(this, Index?) {
        return Index ?? "default"  ; Bracket passes Index to getter
    }
}
```

---

## When to Use This Feature

✓ **Create indexable properties** that customize bracket behavior

✓ **Build API-like objects** similar to RegExMatchInfo or built-in types

✓ **Support optional parameters** in property access

✓ **Design flexible configuration objects** with bracket notation

---

## When NOT to Use This Feature

✗ **Simple single-value properties** (use regular properties instead)

✗ **When `__Item` behavior suffices** (use single-param getters)

✗ **For method calls** (use actual methods with parentheses)

---

## Common Patterns

### Pattern 1: Indexed Counter
```ahk
Count[Name?] {
    get(this, Name?) {
        if !IsSet(Name)
            return this._counters.Count
        return this._counters[Name]
    }
}
```

### Pattern 2: Configuration Access
```ahk
Config[Path?] {
    get(this, Path?) {
        if !IsSet(Path)
            return this._config.Clone()
        return this._config[Path]
    }
}
```

### Pattern 3: Multi-Dimensional Array
```ahk
Cell[Row?, Col?] {
    get(this, Row?, Col?) {
        if !IsSet(Row) || !IsSet(Col)
            return this._dimensions
        return this._data[Row][Col]
    }
}
```

---

## Critical Pitfall: BoundFunc

BoundFunc objects don't expose parameter counts, breaking bracket notation:

```ahk
; FAILS
get: ((this, N?) => N).Bind(, "")

; WORKS
get: (this) => (N?) => N
```

See **GUIDE_PropertyDescriptorBracketNotation.md** "The Pitfall" section for details.

---

## Debugging Checklist

- [ ] Getter has 2+ parameters?
- [ ] Used optional parameter syntax: `Param?` not `Param`?
- [ ] Avoid BoundFunc (use explicit wrapper)?
- [ ] Tested both `obj.Prop` and `obj.Prop[value]` access?
- [ ] Added `IsSet()` checks for optional params?
- [ ] Included error handling for invalid indices?

---

## Related Resources

### In This Project
- `AHK_OOP/Module_ClassPrototyping.md` - Property descriptor fundamentals
- `AHK_OOP/Module_DynamicProperties.md` - Dynamic property patterns
- `AHK_OOP/Module_Objects.md` - Object property access

### External
- [AutoHotkey v2 Docs](https://www.autohotkey.com)
- [Property Descriptors](https://www.autohotkey.com/docs/v2/misc/Classes.htm#DefineProp)
- Built-in examples: `RegExMatchInfo.Len`, `RegExMatchInfo.Pos`

---

## File Structure

```
AutoHotkey/
└── notes/
    ├── README.md (this file)
    ├── GUIDE_PropertyDescriptorBracketNotation.md (comprehensive)
    ├── GUIDE_PropertyDescriptorQuickReference.md (quick lookup)
    ├── EXAMPLE_PropertyDescriptorBracketNotation.ahk (runnable code)
    └── INTEGRATION_PropertyDescriptorBracketNotation.md (module integration)
```

---

## Version Information

- **AutoHotkey Version:** v2.0+
- **Created:** 2025-10-16
- **Last Updated:** 2025-10-16
- **Status:** Complete and tested

---

## Questions?

Refer to the troubleshooting sections in:
- **GUIDE_PropertyDescriptorQuickReference.md** (quick answers)
- **GUIDE_PropertyDescriptorBracketNotation.md** (detailed explanations)

---

## Summary

This collection answers one of AutoHotkey v2's most powerful and least-understood features. Whether you're implementing a new API, optimizing property access, or understanding how AHK v2's built-ins work, these guides provide comprehensive coverage.

**Start with the guide appropriate for your available time, then refer back as needed.**
