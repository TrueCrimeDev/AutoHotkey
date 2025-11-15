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

### Including the shared examples in your scripts

All runnable examples live in `notes/property-descriptor/EXAMPLE_PropertyDescriptorBracketNotation.ahk`. To load them from a
script or test, include the module relative to the file you are running. Examples:

```autohotkey
; From scripts/PropertyDescriptorDemo.ahk
#Include "..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; From Tests/PropertyDescriptorTests/Test_*.ahk
#Include "..\\..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"
```

Once included, you can instantiate the example utilities directly:

```autohotkey
cfg := ConfigManager()
cfg.Set("api.timeout", 30)
MsgBox cfg.Get["api.timeout"]
```

Refer to `scripts/PropertyDescriptorDemo.ahk` for a simple walkthrough and
`Tests/PropertyDescriptorTests/*.ahk` for assertion-based usage patterns.

## Related Projects

This PropertyDescriptor implementation is separate from but related to the [debugger system](../debugger/) in this repository.

---

**Last Updated**: 2025-10-23  
**Status**: Complete Implementation