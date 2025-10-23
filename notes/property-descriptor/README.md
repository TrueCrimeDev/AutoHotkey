# PropertyDescriptor Bracket Notation

> AutoHotkey v2 PropertyDescriptor implementation with bracket notation support

## Overview

This directory contains the AutoHotkey v2 PropertyDescriptor bracket notation implementation, including documentation, examples, and integration guides.

## Files

### Documentation
- **[GUIDE_PropertyDescriptorBracketNotation.md](GUIDE_PropertyDescriptorBracketNotation.md)** - Complete implementation guide
- **[GUIDE_PropertyDescriptorQuickReference.md](GUIDE_PropertyDescriptorQuickReference.md)** - Quick reference guide
- **[INTEGRATION_PropertyDescriptorBracketNotation.md](INTEGRATION_PropertyDescriptorBracketNotation.md)** - Integration instructions

### Examples
- **[EXAMPLE_PropertyDescriptorBracketNotation.ahk](EXAMPLE_PropertyDescriptorBracketNotation.ahk)** - Practical usage examples

## Purpose

The PropertyDescriptor bracket notation system allows for dynamic property access and manipulation in AutoHotkey v2, providing:

- Dynamic property names
- Computed property access
- Advanced object manipulation
- Enhanced metaprogramming capabilities

## Quick Example

```autohotkey
; Create an object with dynamic properties
obj := Map()
obj["dynamic_" . A_Now] := "value"

; Access using bracket notation
key := "dynamic_" . A_Now
value := obj[key]

; PropertyDescriptor usage
descriptor := {get: Func("myGetter"), set: Func("mySetter")}
Object.defineProperty(obj, "computedProp", descriptor)
```

## Usage

1. **Read the main guide**: Start with [GUIDE_PropertyDescriptorBracketNotation.md](GUIDE_PropertyDescriptorBracketNotation.md)
2. **Check the quick reference**: Use [GUIDE_PropertyDescriptorQuickReference.md](GUIDE_PropertyDescriptorQuickReference.md) for syntax lookup
3. **Study examples**: Review [EXAMPLE_PropertyDescriptorBracketNotation.ahk](EXAMPLE_PropertyDescriptorBracketNotation.ahk) for practical usage
4. **Integration help**: Follow [INTEGRATION_PropertyDescriptorBracketNotation.md](INTEGRATION_PropertyDescriptorBracketNotation.md) for implementation

## Related Projects

This PropertyDescriptor implementation is separate from but related to the [debugger system](../debugger/) in this repository.

---

**Last Updated**: 2025-10-23  
**Status**: Complete Implementation