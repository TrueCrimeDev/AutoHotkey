# The Ultimate Guide to Property Descriptors with Bracket Notation in AutoHotkey v2

## The Ultimate Question

**"How can I create a property descriptor that accepts optional parameters through bracket notation, like `RegExMatchInfo.Len[N]`, where the brackets pass arguments directly to the property getter rather than calling `__Item` on the returned value?"**

This guide answers that question comprehensively and explores the hidden mechanics of AHK v2's property access system.

---

## Table of Contents

1. [The Mystery](#the-mystery)
2. [The Discovery](#the-discovery)
3. [The Mechanics](#the-mechanics)
4. [The Pitfall](#the-pitfall)
5. [The Solution](#the-solution)
6. [Practical Implementation](#practical-implementation)
7. [Real-World Patterns](#real-world-patterns)
8. [Common Mistakes](#common-mistakes)
9. [Testing and Validation](#testing-and-validation)

---

## The Mystery

In AutoHotkey v2, when you access a property like:
```ahk
result := obj.property[index]
```

Two very different things could happen:

### Scenario 1: Bracket Calls `__Item` (Default Behavior)
```ahk
class Container {
    _data := Map()

    Items {
        get {
            return this._data  ; Returns the Map itself
        }
    }
}

c := Container()
c.Items[5] := "Value"           ; Calls _data.__Item(5) for assignment
MsgBox c.Items[5]               ; Calls _data.__Item(5) for retrieval
```

Here, the bracket notation acts on the **returned object**, calling its `__Item` method.

### Scenario 2: Bracket Passes to Getter (Advanced)
```ahk
class RegExMatcher {
    _matches := ["Full", "Group1", "Group2"]

    ; This getter accepts optional parameters!
    Len[N?] {
        get {
            if !IsSet(N)
                return this._matches.Length           ; Total matches
            return StrLen(this._matches[N])           ; Length of Nth match
        }
    }
}

m := RegExMatcher()
MsgBox m.Len                    ; Returns: 3
MsgBox m.Len[1]                 ; Returns: 4 (length of "Full")
MsgBox m.Len[2]                 ; Returns: 6 (length of "Group1")
```

Here, the bracket notation **passes the index directly to the getter itself**.

## The Discovery

AHK v2's parser uses a sophisticated routing mechanism based on **getter parameter counts** to decide which behavior applies:

### The Parameter Count Rule

When you write `obj.property[index]`:

1. **Single-Parameter Getter** (`get { ... }` or `get(this)`)
   - Bracket calls `__Item` on the returned object
   - Index never reaches the getter
   - Getter receives only `this`

2. **Multi-Parameter Getter** (`get(this, param?)` or `get(this, param1?, param2?)`)
   - Bracket passes arguments directly to the getter
   - Index reaches the getter as parameters
   - Getter receives `this` plus bracket arguments

### Code Illustration

```ahk
class PropertyRouting {
    ; SINGLE PARAM - bracket acts on returned value
    Single[Index] {
        get {
            MsgBox "Single getter called (no Index parameter)"
            return Map(1, "A", 2, "B", 3, "C")  ; Returns a Map
        }
    }

    ; MULTI PARAM - bracket passes to getter
    Multi[Index] {
        get {
            if IsSet(Index)
                MsgBox "Multi getter called with Index: " Index
            else
                MsgBox "Multi getter called without Index"
            return "result"
        }
    }
}

obj := PropertyRouting()

; Single-param scenario
MsgBox obj.Single[1]              ; Returns "A" (from Map.__Item)
                                  ; Getter receives no Index parameter

; Multi-param scenario
MsgBox obj.Multi[1]               ; Returns "result"
                                  ; Getter receives Index=1 as parameter
```

## The Mechanics

### How AHK v2 Inspects Parameter Counts

The parser inspects getter definitions to determine routing behavior:

```ahk
; These are treated IDENTICALLY (single-param):
MyProperty {
    get {
        return Map()
    }
}

MyProperty {
    get(this) {
        return Map()
    }
}

; These are treated DIFFERENTLY (multi-param - brackets pass through):
MyProperty[N] {
    get {
        ; N is available here if accessed with brackets
        return Map()
    }
}

MyProperty[N?] {
    get(this, N?) {
        ; N is available here if accessed with brackets
        return Map()
    }
}

MyProperty[A?, B?] {
    get(this, A?, B?) {
        ; A and B are available if accessed with brackets
        return Map()
    }
}
```

### Context Matters: Statement vs Expression

How you access a property determines evaluation:

```ahk
class ContextAware {
    Data[Index?] {
        get {
            if IsSet(Index)
                return "Got index: " Index
            return "No index"
        }
    }
}

obj := ContextAware()

; EXPRESSION CONTEXT - evaluates the getter
value := obj.Data
; Result: "No index" (getter called with no parameters)

; BRACKET ACCESS - passes index to getter
value := obj.Data[5]
; Result: "Got index: 5" (getter called with Index=5)

; EXPLICIT CALL - same as no bracket
value := obj.Data[]
; Result: "No index" (getter called with no parameters)
```

## The Pitfall

### BoundFunc Parameter Inspection Issue

There's a critical limitation when using `BoundFunc` objects in property descriptors:

```ahk
; THIS FAILS - BoundFunc doesn't expose MinParams/MaxParams
Getter := ((this, Index?) => Index ?? "no index").Bind(, "")
Test.DefineProp("Broken", { get: Getter })

MsgBox Test.Broken[5]
; Error: Too many parameters
; AHK can't inspect the BoundFunc's parameter count
```

**Why?** AHK inspects `MinParams` and `MaxParams` to decide routing. BoundFunc objects have incomplete reflection metadata, so AHK can't determine if they accept additional parameters.

### Workaround: Explicit Wrapper

```ahk
; WORKS - Explicit function wrapper allows parameter detection
Test.DefineProp("Fixed", {
    get: (this) => (idx) => idx
})

MsgBox Test.Fixed()[5]  ; Returns 5
; The outer getter has 1 parameter (this)
; The returned function accepts the index parameter
```

Or use a proper multi-parameter getter:

```ahk
; WORKS - Direct multi-parameter getter
Test.DefineProp("Working", {
    get(this, Index?) {
        return Index ?? "no index"
    }
})

MsgBox Test.Working[5]  ; Returns 5
```

---

## The Solution

### Core Pattern: Multi-Parameter Property Getters

The solution is to define property getters with **optional parameters**:

```ahk
class RegExMatchInfo {
    ; Store matches
    _matches := []
    _marks := []

    ; Constructor for demonstration
    __New(matches, marks) {
        this._matches := matches
        this._marks := marks
    }

    ; Multi-parameter getter - brackets pass N to getter
    Len[N?] {
        get {
            if !IsSet(N) {
                ; No index: return total count
                return this._matches.Length
            }

            ; With index: return length of specific match
            if (N < 1 || N > this._matches.Length)
                throw IndexError("Match index out of range")

            return StrLen(this._matches[N])
        }
    }

    ; Another example: Mark property
    Mark[N?] {
        get {
            if !IsSet(N) {
                ; Return all marks as array
                return this._marks.Clone()
            }

            ; Return specific mark
            return this._marks[N] ?? -1
        }
    }
}

; Usage
regex := A_RegExVersion()  ; For example
matches := ["FullMatch", "Group1", "Group2"]
marks := [0, 4, 10]
info := RegExMatchInfo(matches, marks)

MsgBox info.Len              ; 3 (total matches)
MsgBox info.Len[1]           ; 9 (length of "FullMatch")
MsgBox info.Len[2]           ; 6 (length of "Group1")

MsgBox info.Mark             ; Cloned marks array
MsgBox info.Mark[1]          ; 0
```

---

## Practical Implementation

### Pattern 1: Indexable Counter Property

```ahk
class MultiCounter {
    _counters := Map()

    Count[Name?] {
        get {
            if !IsSet(Name) {
                ; Return all counts
                result := Map()
                for k, v in this._counters
                    result[k] := v
                return result
            }

            ; Return specific count
            return this._counters.Get(Name, 0)
        }
    }
}

counter := MultiCounter()
counter._counters["clicks"] := 42
counter._counters["views"] := 100

MsgBox counter.Count["clicks"]  ; 42
```

### Pattern 2: Indexed Configuration

```ahk
class Config {
    _config := Map()

    Get[Path?] {
        get {
            if !IsSet(Path)
                return this._config.Clone()

            ; Simple path resolution
            value := this._config.Get(Path, unset)
            if IsSet(value)
                return value

            throw ValueError("Config path '" Path "' not found")
        }
    }

    Set[Path?, Value?] {
        set {
            if !IsSet(Path)
                throw ValueError("Set requires a path parameter")

            this._config[Path] := Value
        }
    }
}

cfg := Config()
cfg.Get["database.host"] := "localhost"
cfg.Get["database.port"] := 5432

MsgBox cfg.Get["database.host"]  ; "localhost"
```

### Pattern 3: Multi-Dimensional Access

```ahk
class Matrix {
    _data := []  ; 1D array for 2D data
    _rows := 0
    _cols := 0

    __New(rows, cols) {
        this._rows := rows
        this._cols := cols
        Loop rows * cols
            this._data.Push(0)
    }

    Value[Row?, Col?] {
        get {
            if !IsSet(Row) {
                ; Return dimensions
                return { rows: this._rows, cols: this._cols }
            }

            if !IsSet(Col)
                throw ValueError("Matrix access requires both row and column")

            if (Row < 1 || Row > this._rows || Col < 1 || Col > this._cols)
                throw IndexError("Index out of bounds")

            index := (Row - 1) * this._cols + Col
            return this._data[index]
        }
        set {
            if !IsSet(Row) || !IsSet(Col)
                throw ValueError("Matrix assignment requires row and column")

            index := (Row - 1) * this._cols + Col
            this._data[index] := value
        }
    }
}

m := Matrix(3, 3)
m.Value[1, 2] := 5
m.Value[2, 1] := 7

MsgBox m.Value[1, 2]  ; 5
MsgBox m.Value        ; {rows: 3, cols: 3}
```

---

## Real-World Patterns

### Pattern A: RegExMatchInfo-Style Implementation

```ahk
class RegExResult {
    _match := ""      ; Full match
    _offset := 0      ; Position in original string
    _length := 0      ; Length of full match
    _captures := []   ; Array of capture groups

    __New(fullMatch, offset, length, captures := []) {
        this._match := fullMatch
        this._offset := offset
        this._length := length
        this._captures := captures
    }

    ; Mimics RegExMatchInfo.Len
    Len[N?] {
        get {
            if !IsSet(N) {
                ; Total captures + 1 for the full match
                return this._captures.Length + 1
            }

            if (N = 0)
                return this._length  ; Length of full match

            if (N < 1 || N > this._captures.Length)
                throw IndexError("Capture group " N " not found")

            return StrLen(this._captures[N])
        }
    }

    ; Mimics RegExMatchInfo.Pos
    Pos[N?] {
        get {
            if !IsSet(N) {
                return this._offset
            }

            if (N = 0)
                return this._offset

            if (N < 1 || N > this._captures.Length)
                throw IndexError("Capture group " N " not found")

            ; This would require additional tracking in real implementation
            return -1  ; Not tracked in this simplified version
        }
    }
}

; Usage
result := RegExResult("FullMatch", 1, 9, ["Group1", "Group2", "Group3"])

MsgBox result.Len              ; 4 (full + 3 groups)
MsgBox result.Len[0]           ; 9 (full match length)
MsgBox result.Len[1]           ; 6 (length of "Group1")
```

### Pattern B: Versioned Property Access

```ahk
class VersionedData {
    _history := []             ; Array of snapshots
    _current := 0              ; Current version index

    __New() {
        this._history.Push(Map())  ; Version 0
    }

    ; Get data from any version
    Version[V?] {
        get {
            if !IsSet(V)
                return this._current  ; Return current version number

            if (V < 0 || V >= this._history.Length)
                throw IndexError("Version " V " not found")

            return this._history[V + 1]  ; +1 because arrays are 1-indexed
        }
    }
}

data := VersionedData()
data.Version[][A_Now] := "version0"  ; Store in current

MsgBox data.Version           ; 0
MsgBox data.Version[0]        ; Returns the Map from version 0
```

---

## Common Mistakes

### Mistake 1: Forgetting the Optional Parameter Syntax

```ahk
; WRONG - Parameter not marked as optional
MyProperty[N] {
    get(this, N) {              ; N is REQUIRED
        return N
    }
}

obj.MyProperty[5]  ; Error: Not enough parameters (need at least 1)

; CORRECT - Parameter marked as optional
MyProperty[N] {
    get(this, N?) {             ; N is OPTIONAL
        return N ?? "no index"
    }
}

obj.MyProperty[5]  ; Works: returns 5
obj.MyProperty     ; Works: returns "no index"
```

### Mistake 2: Using BoundFunc Without Wrapper

```ahk
; WRONG - BoundFunc doesn't expose parameters
Test.DefineProp("Broken", {
    get: ((this, N?) => N ?? "none").Bind(, "")
})

MsgBox Test.Broken[5]  ; Error: Too many parameters

; CORRECT - Use explicit wrapper
Test.DefineProp("Fixed", {
    get: (this) => (N?) => N ?? "none"
})

MsgBox Test.Fixed()[5]  ; Works: returns 5
```

### Mistake 3: Confusing Getter vs __Item

```ahk
; WRONG - Expecting __Item to receive the index
class Wrong {
    Numbers[N] {
        get {
            ; This getter has only 1 parameter (this)
            ; Bracket will call __Item on returned value
            return Map(1, "A", 2, "B")
        }
    }

    __Item[Index] {
        ; This won't be called by Numbers[N] access
        return "This won't happen"
    }
}

; CORRECT - Multi-param getter for bracket access
class Correct {
    Numbers[N] {
        get(this, N?) {
            ; This getter has 2 parameters
            ; Bracket will pass index to getter
            return N ?? "All"
        }
    }
}
```

---

## Testing and Validation

### Test Suite for Property Descriptor Bracket Notation

```ahk
TestPropertyDescriptors() {
    class TestClass {
        _data := [10, 20, 30]

        ; Single-param getter - bracket calls __Item
        Single[N] {
            get {
                return Map(1, "X", 2, "Y", 3, "Z")
            }
        }

        ; Multi-param getter - bracket passes to getter
        Multi[N?] {
            get {
                if !IsSet(N)
                    return this._data.Clone()
                return this._data[N]
            }
        }
    }

    obj := TestClass()

    ; Test 1: Single-param with bracket
    result := obj.Single[1]
    assert(result = "X", "Single[1] should return X from Map.__Item")

    ; Test 2: Multi-param without bracket
    result := obj.Multi
    assert(result.Length = 3, "Multi should return cloned array")

    ; Test 3: Multi-param with bracket
    result := obj.Multi[2]
    assert(result = 20, "Multi[2] should return 20 from getter parameter")

    ; Test 4: Multi-param empty bracket
    result := obj.Multi[]
    assert(result.Length = 3, "Multi[] should return cloned array")

    MsgBox "All tests passed!"
}

assert(condition, message) {
    if !condition
        throw Error(message)
}

TestPropertyDescriptors()
```

---

## Summary: The Ultimate Answer

### Direct Answer

To create a property descriptor where **brackets pass arguments directly to the getter** (not call `__Item` on the returned value):

**Define a property getter with multiple optional parameters:**

```ahk
MyProperty[Index?, Extra?] {
    get {
        ; Access Index and Extra directly
        if !IsSet(Index)
            return "No parameters"
        return "Got index: " Index
    }
}

; Usage
MsgBox obj.MyProperty         ; "No parameters"
MsgBox obj.MyProperty[5]      ; "Got index: 5"
MsgBox obj.MyProperty[5, 10]  ; "Got index: 5"
```

### Why This Works

AHK v2's parser inspects getter parameter counts:
- **1 parameter** (`this` only) → brackets call `__Item`
- **2+ parameters** (with optional params) → brackets pass arguments

### Common Pitfalls to Avoid

1. **BoundFunc limitation**: Can't use `BoundFunc` objects directly; wrap with explicit function
2. **Missing optional markers**: Use `Index?` not `Index` to allow bracket-less access
3. **Context confusion**: Statement vs expression context affects evaluation
4. **Parameter inspection**: AHK must be able to detect parameter counts (avoid BoundFunc)

### Real-World Application

This pattern powers AHK v2 built-ins like:
- `RegExMatchInfo.Len[N]` - Get length of full match or capture group
- `RegExMatchInfo.Pos[N]` - Get position of full match or capture group
- `Match.Len` - Array-like indexed access with optional parameters

Now you understand one of AHK v2's most powerful and hidden features!

---

## Related Concepts

- **Property Descriptors**: Module_ClassPrototyping.md in your project
- **Meta-Functions**: `__Get` and `__Set` for fully dynamic properties
- **Closures**: Capture state in descriptor functions
- **Function Parameters**: Optional parameters enable flexible APIs
