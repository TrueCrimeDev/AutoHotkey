; Property Descriptor Bracket Notation - Practical Examples
; AutoHotkey v2 | Demonstrates multi-parameter getters with bracket access
; ==============================================================================

; EXAMPLE 1: Basic Bracket Parameter Passing
; ==============================================================================
class BasicExample {
    Data[Index?] {
        get(this, Index?) {
            if !IsSet(Index)
                return "All data requested"
            return "Index: " Index
        }
    }
}

TestBasic() {
    obj := BasicExample()
    MsgBox obj.Data          ; "All data requested"
    MsgBox obj.Data[5]       ; "Index: 5"
    MsgBox obj.Data[]        ; "All data requested"
}

; EXAMPLE 2: Array-Like Property Access
; ==============================================================================
class ArrayProperty {
    _items := [10, 20, 30, 40, 50]

    ; Single-parameter getter - bracket calls __Item
    SingleParam[N] {
        get {
            return Map(1, "A", 2, "B", 3, "C")
        }
    }

    ; Multi-parameter getter - bracket passes to getter
    MultiParam[N?] {
        get(this, N?) {
            if !IsSet(N)
                return this._items.Clone()

            if (N < 1 || N > this._items.Length)
                throw IndexError("Index " N " out of range")

            return this._items[N]
        }
    }
}

TestArrayProperty() {
    obj := ArrayProperty()

    ; Single-param: bracket calls Map.__Item
    MsgBox obj.SingleParam[1]      ; "A" (from Map)

    ; Multi-param: bracket passes to getter
    MsgBox obj.MultiParam          ; Array with 5 items
    MsgBox obj.MultiParam[2]       ; 20 (second item)
    MsgBox obj.MultiParam[5]       ; 50 (fifth item)
}

; EXAMPLE 3: RegExMatchInfo-Style Implementation
; ==============================================================================
class RegExResult {
    _fullMatch := ""
    _captures := []
    _offsets := []

    __New(fullMatch, captures, offsets) {
        this._fullMatch := fullMatch
        this._captures := captures
        this._offsets := offsets
    }

    ; Mimic RegExMatchInfo.Len[N]
    Len[N?] {
        get(this, N?) {
            if !IsSet(N) {
                ; Return total count: full match + capture groups
                return this._captures.Length + 1
            }

            if (N = 0)
                return StrLen(this._fullMatch)

            if (N < 1 || N > this._captures.Length)
                throw IndexError("Capture group " N " not found")

            return StrLen(this._captures[N])
        }
    }

    ; Mimic RegExMatchInfo.Pos[N]
    Pos[N?] {
        get(this, N?) {
            if !IsSet(N) {
                return 1  ; Position of full match
            }

            if (N = 0)
                return 1

            if (N < 1 || N > this._offsets.Length)
                throw IndexError("Capture group " N " not found")

            return this._offsets[N]
        }
    }
}

TestRegExResult() {
    result := RegExResult(
        "FullMatch",
        ["Group1", "Group2", "Group3"],
        [1, 10, 15]
    )

    MsgBox result.Len              ; 4 (full + 3 groups)
    MsgBox result.Len[0]           ; 9 (length of "FullMatch")
    MsgBox result.Len[1]           ; 6 (length of "Group1")
    MsgBox result.Pos              ; 1
    MsgBox result.Pos[1]           ; 1 (first group offset)
}

; EXAMPLE 4: Configuration Access Pattern
; ==============================================================================
class ConfigManager {
    _config := Map()

    ; Get configuration value or all values
    Get[Path?] {
        get(this, Path?) {
            if !IsSet(Path)
                return this._config.Clone()

            if !this._config.Has(Path)
                throw KeyError("Config path '" Path "' not found")

            return this._config[Path]
        }
    }

    ; Convenience method to set config
    Set(path, value) {
        this._config[path] := value
    }
}

TestConfigManager() {
    cfg := ConfigManager()
    cfg.Set("database.host", "localhost")
    cfg.Set("database.port", 5432)
    cfg.Set("api.timeout", 30)

    ; Get all config
    allConfig := cfg.Get
    MsgBox allConfig.Count         ; 3 items

    ; Get specific value
    MsgBox cfg.Get["database.host"]  ; "localhost"
    MsgBox cfg.Get["database.port"]  ; 5432
}

; EXAMPLE 5: Multi-Dimensional Array Access
; ==============================================================================
class Matrix {
    _rows := 0
    _cols := 0
    _data := []

    __New(rows, cols) {
        this._rows := rows
        this._cols := cols
        Loop rows * cols
            this._data.Push(0)
    }

    ; Access matrix element
    Value[Row?, Col?] {
        get(this, Row?, Col?) {
            if !IsSet(Row) || !IsSet(Col) {
                return { rows: this._rows, cols: this._cols }
            }

            if (Row < 1 || Row > this._rows || Col < 1 || Col > this._cols)
                throw IndexError("Matrix index out of bounds")

            index := (Row - 1) * this._cols + Col
            return this._data[index]
        }

        set {
            if !IsSet(Row) || !IsSet(Col)
                throw ValueError("Matrix assignment requires row and col")

            index := (Row - 1) * this._cols + Col
            this._data[index] := value
        }
    }
}

TestMatrix() {
    m := Matrix(3, 3)

    ; Set values
    m.Value[1, 1] := 1
    m.Value[1, 2] := 2
    m.Value[2, 1] := 3
    m.Value[2, 2] := 4

    ; Get dimensions
    MsgBox m.Value.rows            ; 3
    MsgBox m.Value.cols            ; 3

    ; Get values
    MsgBox m.Value[1, 1]           ; 1
    MsgBox m.Value[2, 2]           ; 4
}

; EXAMPLE 6: Counter with Indexed Access
; ==============================================================================
class MultiCounter {
    _counters := Map()

    Count[Name?] {
        get(this, Name?) {
            if !IsSet(Name) {
                ; Return all counters as a cloned map
                result := Map()
                for k, v in this._counters
                    result[k] := v
                return result
            }

            return this._counters.Get(Name, 0)
        }
    }

    Increment(name) {
        this._counters[name] := this._counters.Get(name, 0) + 1
    }
}

TestMultiCounter() {
    counter := MultiCounter()

    counter.Increment("clicks")
    counter.Increment("clicks")
    counter.Increment("views")

    MsgBox counter.Count["clicks"]      ; 2
    MsgBox counter.Count["views"]       ; 1

    allCounts := counter.Count          ; Get all
    MsgBox allCounts.Count              ; 2 counters
}

; EXAMPLE 7: BoundFunc Pitfall and Workaround
; ==============================================================================
class BoundFuncPitfall {
    ; WRONG: BoundFunc doesn't expose parameter count
    Wrong {
        get => ((this, N?) => N ?? "none").Bind(, "")
    }

    ; CORRECT: Explicit wrapper exposes parameter count
    Correct {
        get => (this) => (N?) => N ?? "none"
    }
}

TestBoundFuncPitfall() {
    obj := BoundFuncPitfall()

    ; This would error: obj.Wrong[5]
    ; Error: Too many parameters

    ; This works:
    MsgBox obj.Correct()[5]             ; 5
}

; EXAMPLE 8: Versioned Data Access
; ==============================================================================
class VersionedStorage {
    _versions := []
    _current := 0

    __New() {
        this._versions.Push(Map())      ; Version 0
    }

    Version[V?] {
        get(this, V?) {
            if !IsSet(V)
                return this._current

            if (V < 0 || V >= this._versions.Length)
                throw IndexError("Version " V " not found")

            return this._versions[V + 1]  ; +1 for 1-indexing
        }
    }

    StoreCurrentVersion() {
        this._versions.Push(Map())
        this._current++
    }
}

TestVersionedStorage() {
    storage := VersionedStorage()

    ; Store data in version 0
    storage.Version[0]["key1"] := "value1"

    ; Create new version
    storage.StoreCurrentVersion()
    storage.Version[1]["key2"] := "value2"

    MsgBox storage.Version             ; Current: 1
    MsgBox storage.Version[0].Count    ; Version 0 has 1 item
    MsgBox storage.Version[1].Count    ; Version 1 has 1 item
}

; EXAMPLE 9: Parameter Validation in Getter
; ==============================================================================
class ValidatedAccess {
    _data := [100, 200, 300]

    Item[Index?] {
        get(this, Index?) {
            if !IsSet(Index)
                return this._data.Length

            ; Validate index
            if !IsInteger(Index)
                throw TypeError("Index must be an integer")

            if (Index < 1 || Index > this._data.Length)
                throw IndexError("Index " Index " out of bounds")

            return this._data[Index]
        }
    }
}

TestValidatedAccess() {
    obj := ValidatedAccess()

    MsgBox obj.Item              ; 3 (count)
    MsgBox obj.Item[1]           ; 100

    try
        MsgBox obj.Item[10]      ; Will throw IndexError
    catch Error as err
        MsgBox "Caught error: " err.What
}

; EXAMPLE 10: Comparison - Single vs Multi Parameter
; ==============================================================================
class ParameterComparison {
    _items := [10, 20, 30]

    ; Single-param getter
    Single[N] {
        get {
            ; N is not accessible here
            ; Bracket will call __Item on returned Map
            return Map(1, "X", 2, "Y", 3, "Z")
        }
    }

    ; Multi-param getter
    Multi[N?] {
        get(this, N?) {
            ; N is accessible here if bracket was used
            ; If no bracket, N is unset
            if !IsSet(N)
                return this._items.Length
            return this._items[N]
        }
    }
}

TestParameterComparison() {
    obj := ParameterComparison()

    ; Single-param: bracket acts on Map
    MsgBox obj.Single[1]             ; "X" (from Map.__Item)

    ; Multi-param: bracket passes to getter
    MsgBox obj.Multi                 ; 3 (array length)
    MsgBox obj.Multi[1]              ; 10 (first item)
}

; ==============================================================================
; RUN ALL TESTS
; ==============================================================================
RunAllTests() {
    MsgBox "Starting Property Descriptor Examples`n`nClick OK for each example"

    MsgBox "Example 1: Basic Bracket Parameter Passing"
    TestBasic()

    MsgBox "Example 2: Array-Like Property Access"
    TestArrayProperty()

    MsgBox "Example 3: RegExMatchInfo-Style Implementation"
    TestRegExResult()

    MsgBox "Example 4: Configuration Access Pattern"
    TestConfigManager()

    MsgBox "Example 5: Multi-Dimensional Array Access"
    TestMatrix()

    MsgBox "Example 6: Counter with Indexed Access"
    TestMultiCounter()

    MsgBox "Example 7: BoundFunc Pitfall and Workaround"
    TestBoundFuncPitfall()

    MsgBox "Example 8: Versioned Data Access"
    TestVersionedStorage()

    MsgBox "Example 9: Parameter Validation in Getter"
    TestValidatedAccess()

    MsgBox "Example 10: Single vs Multi Parameter"
    TestParameterComparison()

    MsgBox "All examples completed successfully!"
}

; Uncomment to run all tests
; RunAllTests()

; Or run individual tests:
; TestBasic()
; TestArrayProperty()
; TestRegExResult()
; TestConfigManager()
; TestMatrix()
; TestMultiCounter()
; TestBoundFuncPitfall()
; TestVersionedStorage()
; TestValidatedAccess()
; TestParameterComparison()
