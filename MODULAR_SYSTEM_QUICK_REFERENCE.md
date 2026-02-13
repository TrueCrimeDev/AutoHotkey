# Modular System Quick Reference

Ready-to-use templates and code snippets for building modular AutoHotkey v2 systems.

## Table of Contents
1. [Module Templates](#module-templates)
2. [Common Patterns](#common-patterns)
3. [Testing Templates](#testing-templates)
4. [Project Structures](#project-structures)
5. [Utility Snippets](#utility-snippets)

---

## Module Templates

### Basic Module Template

Copy this as starting point for any module:

```ahk
/**
 * ModuleName.ahk
 * Brief description
 *
 * @version 1.0.0
 * @author Your Name
 * @requires AutoHotkey v2.0+
 */

#Requires AutoHotkey >=2.0

; Prevent duplicate includes
if IsSet(ModuleName_Included)
    return
ModuleName_Included := true

; Dependencies (if any)
; #Include <Dependency>

/**
 * Main module class
 */
class ModuleName {
    static VERSION := "1.0.0"

    /**
     * Public method
     * @param {String} input - Description
     * @returns {String} Description
     */
    static DoSomething(input) {
        ; Validate
        if !IsSet(input) || input = ""
            throw ValueError("Input is required", -1)

        ; Implementation
        return "Result: " input
    }

    /**
     * Private helper (prefix with _)
     */
    static _Helper() {
        ; Internal use only
    }
}
```

### Stateful Module Template

For modules that maintain state (singleton pattern):

```ahk
/**
 * ServiceName.ahk
 * Stateful service (singleton)
 */

#Requires AutoHotkey >=2.0

if IsSet(ServiceName_Included)
    return
ServiceName_Included := true

class ServiceName {
    static VERSION := "1.0.0"
    static _instance := ""

    ; Instance state
    _data := Map()
    _config := {}

    /**
     * Get singleton instance
     */
    static Instance {
        get {
            if !ServiceName._instance
                ServiceName._instance := ServiceName()
            return ServiceName._instance
        }
    }

    /**
     * Private constructor (use Instance instead)
     */
    __New() {
        this._Initialize()
    }

    /**
     * Initialize service
     */
    _Initialize() {
        ; Setup code here
    }

    /**
     * Public method (accessed via ServiceName.Instance.Method())
     */
    DoWork() {
        ; Implementation
    }

    /**
     * Static convenience method
     */
    static DoWorkStatic() {
        return ServiceName.Instance.DoWork()
    }
}
```

### Configurable Module Template

Module with external configuration:

```ahk
/**
 * ConfigurableModule.ahk
 * Module with configuration options
 */

#Requires AutoHotkey >=2.0

if IsSet(ConfigurableModule_Included)
    return
ConfigurableModule_Included := true

class ConfigurableModule {
    static VERSION := "1.0.0"

    /**
     * Default configuration (users can override)
     */
    static Config := {
        Option1: "default",
        Option2: 100,
        Option3: true,
        Debug: false
    }

    /**
     * Initialize with custom config
     * @param {Object} userConfig - User configuration
     */
    static Init(userConfig := {}) {
        ; Merge user config with defaults
        for key, value in userConfig.OwnProps() {
            if ConfigurableModule.Config.HasOwnProp(key)
                ConfigurableModule.Config.%key% := value
        }

        if ConfigurableModule.Config.Debug
            OutputDebug("ConfigurableModule initialized with config: " JSON.Stringify(ConfigurableModule.Config))
    }

    /**
     * Method that uses configuration
     */
    static DoSomething() {
        if ConfigurableModule.Config.Option3 {
            ; Do something
        }

        return ConfigurableModule.Config.Option1
    }
}

; Usage:
; ConfigurableModule.Init({Option1: "custom", Debug: true})
; ConfigurableModule.DoSomething()
```

---

## Common Patterns

### Pattern: Event Emitter

```ahk
/**
 * Simple event emitter implementation
 */
class EventEmitter {
    _listeners := Map()

    /**
     * Subscribe to event
     */
    On(eventName, callback) {
        if !this._listeners.Has(eventName)
            this._listeners[eventName] := []
        this._listeners[eventName].Push(callback)
    }

    /**
     * Unsubscribe from event
     */
    Off(eventName, callback) {
        if !this._listeners.Has(eventName)
            return

        listeners := this._listeners[eventName]
        for i, listener in listeners {
            if listener = callback {
                listeners.RemoveAt(i)
                break
            }
        }
    }

    /**
     * Emit event
     */
    Emit(eventName, data := "") {
        if !this._listeners.Has(eventName)
            return

        for callback in this._listeners[eventName]
            callback(data)
    }

    /**
     * Once - listen once then remove
     */
    Once(eventName, callback) {
        wrapper := (data) {
            callback(data)
            this.Off(eventName, wrapper)
        }
        this.On(eventName, wrapper)
    }
}

; Usage:
; emitter := EventEmitter()
; emitter.On("data", (data) => MsgBox("Got: " data))
; emitter.Emit("data", "Hello")
```

### Pattern: Chain Methods

```ahk
/**
 * Method chaining pattern
 */
class QueryBuilder {
    _select := []
    _where := []
    _orderBy := ""

    /**
     * Select fields (chainable)
     */
    Select(fields*) {
        this._select := fields
        return this  ; Return this for chaining
    }

    /**
     * Where condition (chainable)
     */
    Where(condition) {
        this._where.Push(condition)
        return this
    }

    /**
     * Order by (chainable)
     */
    OrderBy(field) {
        this._orderBy := field
        return this
    }

    /**
     * Build final query
     */
    Build() {
        query := "SELECT " (this._select.Length ? Join(this._select, ", ") : "*")

        if this._where.Length
            query .= " WHERE " Join(this._where, " AND ")

        if this._orderBy != ""
            query .= " ORDER BY " this._orderBy

        return query
    }
}

; Helper: Join array with separator
Join(arr, sep) {
    result := ""
    for item in arr
        result .= (result = "" ? "" : sep) item
    return result
}

; Usage:
; query := QueryBuilder()
;     .Select("id", "name", "email")
;     .Where("age > 18")
;     .Where("status = 'active'")
;     .OrderBy("name")
;     .Build()
```

### Pattern: Factory

```ahk
/**
 * Factory pattern for creating objects
 */
class ShapeFactory {
    /**
     * Create shape based on type
     */
    static Create(type, params*) {
        switch type {
            case "circle":
                return Circle(params*)
            case "rectangle":
                return Rectangle(params*)
            case "triangle":
                return Triangle(params*)
            default:
                throw ValueError("Unknown shape type: " type)
        }
    }
}

class Circle {
    radius := 0

    __New(radius) {
        this.radius := radius
    }

    Area() => 3.14159 * this.radius * this.radius
}

class Rectangle {
    width := 0
    height := 0

    __New(width, height) {
        this.width := width
        this.height := height
    }

    Area() => this.width * this.height
}

class Triangle {
    base := 0
    height := 0

    __New(base, height) {
        this.base := base
        this.height := height
    }

    Area() => 0.5 * this.base * this.height
}

; Usage:
; circle := ShapeFactory.Create("circle", 10)
; MsgBox("Circle area: " circle.Area())
```

### Pattern: Observer

```ahk
/**
 * Observer pattern implementation
 */
class Observable {
    _observers := []

    /**
     * Attach observer
     */
    Attach(observer) {
        this._observers.Push(observer)
    }

    /**
     * Detach observer
     */
    Detach(observer) {
        for i, obs in this._observers {
            if obs = observer {
                this._observers.RemoveAt(i)
                break
            }
        }
    }

    /**
     * Notify all observers
     */
    Notify(data) {
        for observer in this._observers
            observer.Update(data)
    }
}

/**
 * Observer interface
 */
class Observer {
    Update(data) {
        ; Override in subclass
        throw Error("Update() must be implemented")
    }
}

; Example: Stock price observable
class Stock extends Observable {
    _price := 0

    Price {
        get => this._price
        set {
            this._price := value
            this.Notify({price: value})
        }
    }
}

class StockDisplay extends Observer {
    Update(data) {
        MsgBox("Price updated: $" data.price)
    }
}

; Usage:
; stock := Stock()
; display := StockDisplay()
; stock.Attach(display)
; stock.Price := 100.50  ; Triggers notification
```

### Pattern: Strategy

```ahk
/**
 * Strategy pattern for interchangeable algorithms
 */
class Context {
    _strategy := ""

    SetStrategy(strategy) {
        this._strategy := strategy
    }

    Execute(data) {
        if !this._strategy
            throw Error("No strategy set")
        return this._strategy.Execute(data)
    }
}

class UpperCaseStrategy {
    Execute(data) => StrUpper(data)
}

class LowerCaseStrategy {
    Execute(data) => StrLower(data)
}

class TitleCaseStrategy {
    Execute(data) => RegExReplace(data, "\b(\w)", (m) => StrUpper(m[1]))
}

; Usage:
; ctx := Context()
; ctx.SetStrategy(UpperCaseStrategy())
; result := ctx.Execute("hello world")  ; "HELLO WORLD"
;
; ctx.SetStrategy(TitleCaseStrategy())
; result := ctx.Execute("hello world")  ; "Hello World"
```

---

## Testing Templates

### Basic Test File

```ahk
/**
 * ModuleNameTests.ahk
 * Tests for ModuleName
 */

#Include <TestFramework>
#Include <ModuleName>

; Test 1: Basic functionality
TestFramework.Test("ModuleName - Basic test", (*) {
    result := ModuleName.DoSomething("input")
    TestFramework.AssertEqual(result, "expected", "Should return expected value")
})

; Test 2: Edge case
TestFramework.Test("ModuleName - Edge case", (*) {
    result := ModuleName.DoSomething("")
    TestFramework.AssertEqual(result, "", "Should handle empty input")
})

; Test 3: Error handling
TestFramework.Test("ModuleName - Error handling", (*) {
    TestFramework.AssertThrows(
        (*) => ModuleName.DoSomething(Invalid),
        "Should throw on invalid input"
    )
})

; Test 4: Configuration
TestFramework.Test("ModuleName - Configuration", (*) {
    original := ModuleName.Config.Option1
    ModuleName.Config.Option1 := "custom"

    result := ModuleName.DoSomething("test")
    TestFramework.AssertEqual(result, "custom", "Should use custom config")

    ; Restore
    ModuleName.Config.Option1 := original
})

; Run all tests if this is the main script
if A_ScriptName = "ModuleNameTests.ahk" {
    results := TestFramework.RunAll()
    MsgBox(Format("Tests complete: {1} passed, {2} failed", results.passed, results.failed))
    ExitApp(results.failed > 0 ? 1 : 0)
}
```

### Test Framework (Minimal)

```ahk
/**
 * TestFramework.ahk
 * Simple testing framework
 */

#Requires AutoHotkey >=2.0

if IsSet(TestFramework_Included)
    return
TestFramework_Included := true

class TestFramework {
    static _tests := []
    static _results := []

    static Test(name, testFunc) {
        TestFramework._tests.Push({name: name, func: testFunc})
    }

    static RunAll() {
        TestFramework._results := []
        passed := 0
        failed := 0

        for test in TestFramework._tests {
            try {
                test.func()
                TestFramework._results.Push({name: test.name, passed: true, error: ""})
                passed++
                OutputDebug("✓ " test.name)
            } catch as err {
                TestFramework._results.Push({name: test.name, passed: false, error: err.Message})
                failed++
                OutputDebug("✗ " test.name " - " err.Message)
            }
        }

        return {passed: passed, failed: failed, results: TestFramework._results}
    }

    static Assert(condition, message := "Assertion failed") {
        if !condition
            throw Error(message)
    }

    static AssertEqual(actual, expected, message := "") {
        if actual != expected {
            msg := message != "" ? message : Format("Expected '{1}', got '{2}'", expected, actual)
            throw Error(msg)
        }
    }

    static AssertNotEqual(actual, notExpected, message := "") {
        if actual = notExpected {
            msg := message != "" ? message : Format("Expected not '{1}'", notExpected)
            throw Error(msg)
        }
    }

    static AssertThrows(func, message := "Expected exception") {
        threw := false
        try {
            func()
        } catch {
            threw := true
        }
        if !threw
            throw Error(message)
    }

    static AssertContains(haystack, needle, message := "") {
        if !InStr(haystack, needle) {
            msg := message != "" ? message : Format("Expected to contain '{1}'", needle)
            throw Error(msg)
        }
    }
}
```

---

## Project Structures

### Structure 1: Simple Project

```
MyScript/
├── MyScript.ahk          # Main entry point
├── config.ini            # Configuration
└── Lib/                  # Local libraries
    ├── Utils.ahk
    └── Helpers.ahk
```

**MyScript.ahk:**
```ahk
#Requires AutoHotkey >=2.0
#Include <Utils>
#Include <Helpers>

; Load config
config := IniRead("config.ini")

; Your script code
MsgBox("Ready!")
```

### Structure 2: Medium Project with Tests

```
MyApp/
├── Main.ahk              # Entry point
├── config.ini
├── README.md
├── Lib/                  # Modules
│   ├── Core/
│   │   ├── App.ahk
│   │   └── Config.ahk
│   └── Utils/
│       ├── String.ahk
│       └── File.ahk
└── Tests/                # Tests
    ├── TestFramework.ahk
    ├── CoreTests.ahk
    └── UtilsTests.ahk
```

**Main.ahk:**
```ahk
#Requires AutoHotkey >=2.0
#Include Lib\Core\App.ahk
#Include Lib\Core\Config.ahk
#Include Lib\Utils\String.ahk
#Include Lib\Utils\File.ahk

App.Start()
```

### Structure 3: Large Project with Plugins

```
MyApplication/
├── Main.ahk
├── config.ini
├── README.md
│
├── Lib/                  # Core modules
│   ├── Core/
│   │   ├── App.ahk
│   │   ├── Config.ahk
│   │   ├── Events.ahk
│   │   └── PluginManager.ahk
│   │
│   ├── UI/
│   │   ├── Components/
│   │   │   ├── Button.ahk
│   │   │   └── Dialog.ahk
│   │   └── Layouts/
│   │       └── Grid.ahk
│   │
│   └── Utils/
│       ├── String.ahk
│       ├── File.ahk
│       └── Http.ahk
│
├── Plugins/              # Optional plugins
│   ├── Logger/
│   │   ├── LogPlugin.ahk
│   │   └── README.md
│   └── Debugger/
│       ├── DebugPlugin.ahk
│       └── README.md
│
├── Tests/
│   ├── TestFramework.ahk
│   ├── RunAllTests.ahk
│   ├── Core/
│   │   └── AppTests.ahk
│   └── Utils/
│       └── StringTests.ahk
│
├── Examples/
│   ├── BasicUsage.ahk
│   └── AdvancedUsage.ahk
│
└── Docs/
    ├── API.md
    └── ARCHITECTURE.md
```

**Main.ahk:**
```ahk
#Requires AutoHotkey >=2.0

; Core includes
#Include Lib\Core\App.ahk
#Include Lib\Core\Config.ahk
#Include Lib\Core\Events.ahk
#Include Lib\Core\PluginManager.ahk

; UI includes
#Include Lib\UI\Components\Button.ahk
#Include Lib\UI\Components\Dialog.ahk

; Utility includes
#Include Lib\Utils\String.ahk
#Include Lib\Utils\File.ahk
#Include Lib\Utils\Http.ahk

; Load plugins
if FileExist("Plugins\Logger\LogPlugin.ahk") {
    #Include Plugins\Logger\LogPlugin.ahk
    PluginManager.Register("logger", LogPlugin)
}

if FileExist("Plugins\Debugger\DebugPlugin.ahk") {
    #Include Plugins\Debugger\DebugPlugin.ahk
    PluginManager.Register("debugger", DebugPlugin)
}

; Start application
App.Start()
```

---

## Utility Snippets

### Snippet: Version Comparison

```ahk
/**
 * Compare two semantic version strings
 * @returns -1 if v1 < v2, 0 if equal, 1 if v1 > v2
 */
CompareVersions(v1, v2) {
    parts1 := StrSplit(v1, ".")
    parts2 := StrSplit(v2, ".")
    maxLen := Max(parts1.Length, parts2.Length)

    loop maxLen {
        p1 := (A_Index <= parts1.Length) ? Integer(parts1[A_Index]) : 0
        p2 := (A_Index <= parts2.Length) ? Integer(parts2[A_Index]) : 0

        if p1 < p2
            return -1
        else if p1 > p2
            return 1
    }

    return 0
}

; Usage:
; result := CompareVersions("1.2.3", "1.3.0")  ; Returns -1
; result := CompareVersions("2.0.0", "1.9.9")  ; Returns 1
; result := CompareVersions("1.0.0", "1.0.0")  ; Returns 0
```

### Snippet: Safe Property Access

```ahk
/**
 * Safely get nested property with default value
 */
GetProperty(obj, path, default := "") {
    parts := StrSplit(path, ".")

    current := obj
    for part in parts {
        if !IsObject(current)
            return default

        if !current.HasOwnProp(part)
            return default

        current := current.%part%
    }

    return current
}

; Usage:
; obj := {user: {profile: {name: "John"}}}
; name := GetProperty(obj, "user.profile.name", "Unknown")  ; "John"
; age := GetProperty(obj, "user.profile.age", 0)  ; 0 (default)
```

### Snippet: Debounce Function

```ahk
/**
 * Debounce a function call
 */
class Debouncer {
    _func := ""
    _delay := 0
    _timer := ""

    __New(func, delay := 300) {
        this._func := func
        this._delay := delay
    }

    Call(params*) {
        if this._timer
            SetTimer(this._timer, 0)  ; Cancel existing timer

        this._timer := () => this._func(params*)
        SetTimer(this._timer, -this._delay)
    }
}

; Usage:
; debouncedFunc := Debouncer((*) => MsgBox("Executed!"), 500)
; debouncedFunc()  ; Called
; debouncedFunc()  ; Cancels previous, reschedules
; debouncedFunc()  ; Cancels previous, reschedules
; ; Only one MsgBox appears after 500ms
```

### Snippet: Simple Cache

```ahk
/**
 * Simple caching utility
 */
class Cache {
    _data := Map()
    _ttl := Map()

    /**
     * Set value with optional TTL (time to live in ms)
     */
    Set(key, value, ttl := 0) {
        this._data[key] := value

        if ttl > 0 {
            this._ttl[key] := A_TickCount + ttl
            ; Set timer to auto-delete
            SetTimer(() => this.Delete(key), -ttl)
        }
    }

    /**
     * Get value
     */
    Get(key, default := "") {
        ; Check if expired
        if this._ttl.Has(key) && A_TickCount > this._ttl[key] {
            this.Delete(key)
            return default
        }

        return this._data.Has(key) ? this._data[key] : default
    }

    /**
     * Delete value
     */
    Delete(key) {
        this._data.Delete(key)
        this._ttl.Delete(key)
    }

    /**
     * Clear all
     */
    Clear() {
        this._data := Map()
        this._ttl := Map()
    }
}

; Usage:
; cache := Cache()
; cache.Set("user", {name: "John"}, 5000)  ; Expires in 5 seconds
; user := cache.Get("user")
```

### Snippet: Retry Logic

```ahk
/**
 * Retry a function with exponential backoff
 */
Retry(func, maxAttempts := 3, initialDelay := 100) {
    attempts := 0
    delay := initialDelay

    loop maxAttempts {
        attempts++
        try {
            return func()
        } catch as err {
            if attempts >= maxAttempts
                throw err

            OutputDebug(Format("Attempt {1} failed: {2}. Retrying in {3}ms...",
                attempts, err.Message, delay))

            Sleep(delay)
            delay *= 2  ; Exponential backoff
        }
    }
}

; Usage:
; result := Retry(() => HttpClient.Get("https://api.example.com/data"), 5, 1000)
```

### Snippet: Simple Logger

```ahk
/**
 * Simple file logger
 */
class Logger {
    static _file := A_ScriptDir "\app.log"
    static _level := "INFO"
    static _levels := ["DEBUG", "INFO", "WARN", "ERROR"]

    static SetFile(path) => Logger._file := path
    static SetLevel(level) => Logger._level := level

    static Debug(msg) => Logger._Log("DEBUG", msg)
    static Info(msg) => Logger._Log("INFO", msg)
    static Warn(msg) => Logger._Log("WARN", msg)
    static Error(msg) => Logger._Log("ERROR", msg)

    static _Log(level, msg) {
        ; Only log if level is >= current level
        currentIndex := 0
        levelIndex := 0

        for i, l in Logger._levels {
            if l = Logger._level
                currentIndex := i
            if l = level
                levelIndex := i
        }

        if levelIndex < currentIndex
            return

        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        line := Format("[{1}] {2}: {3}`n", timestamp, level, msg)
        FileAppend(line, Logger._file)
    }
}

; Usage:
; Logger.SetLevel("INFO")
; Logger.Debug("This won't be logged")
; Logger.Info("This will be logged")
; Logger.Error("Error occurred!")
```

---

## Quick Copy-Paste: Complete Minimal Setup

### File 1: Main.ahk

```ahk
#Requires AutoHotkey >=2.0

; Include your modules
#Include <MyModule>

; Configure if needed
MyModule.Config.Option1 := "custom"

; Use your module
result := MyModule.DoSomething("test")
MsgBox(result)
```

### File 2: Lib\MyModule.ahk

```ahk
#Requires AutoHotkey >=2.0

if IsSet(MyModule_Included)
    return
MyModule_Included := true

class MyModule {
    static VERSION := "1.0.0"

    static Config := {
        Option1: "default"
    }

    static DoSomething(input) {
        if !IsSet(input)
            throw ValueError("Input required")

        return MyModule.Config.Option1 ": " input
    }
}
```

### File 3: Tests\MyModuleTests.ahk

```ahk
#Include ..\Lib\MyModule.ahk
#Include TestFramework.ahk

TestFramework.Test("Basic test", (*) {
    result := MyModule.DoSomething("test")
    TestFramework.AssertEqual(result, "default: test")
})

if A_ScriptName = "MyModuleTests.ahk"
    TestFramework.RunAll()
```

---

## Best Practices Checklist

When creating a module, ensure:

- [ ] Module name is clear and descriptive
- [ ] Header comment with description, version, author, dependencies
- [ ] Uses `#Requires AutoHotkey >=2.0`
- [ ] Has include guard (`if IsSet(ModuleName_Included) return`)
- [ ] Includes VERSION property
- [ ] All public methods are documented
- [ ] Input validation on all public methods
- [ ] Consistent naming (PascalCase for classes/methods)
- [ ] Private methods prefixed with underscore (_Helper)
- [ ] Configuration is exposed as static Config object
- [ ] No global variables (use class properties)
- [ ] Includes usage examples in comments
- [ ] Has corresponding test file
- [ ] README.md with installation and usage
- [ ] Follows semantic versioning

---

**Quick Reference Complete!** Use these templates as starting points for your modular AutoHotkey system.
