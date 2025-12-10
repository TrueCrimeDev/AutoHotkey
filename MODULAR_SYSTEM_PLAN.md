# Comprehensive Plan: Modular System Architecture for AutoHotkey v2

## Table of Contents
1. [Overview](#overview)
2. [Understanding AHK's Import System](#understanding-ahks-import-system)
3. [Design Principles](#design-principles)
4. [Folder Structure Conventions](#folder-structure-conventions)
5. [Module Patterns & Types](#module-patterns--types)
6. [Dependency Management](#dependency-management)
7. [Versioning & Compatibility](#versioning--compatibility)
8. [Testing Strategy](#testing-strategy)
9. [Documentation Standards](#documentation-standards)
10. [Distribution Methods](#distribution-methods)
11. [Implementation Examples](#implementation-examples)
12. [Best Practices](#best-practices)

---

## Overview

### Goals
- Create reusable, maintainable AutoHotkey modules
- Build a plugin/extension architecture
- Enable easy sharing and distribution of functionality
- Support dependency management
- Maintain backward compatibility
- Facilitate testing and documentation

### Time Estimate
- **Planning & Setup**: 2-3 hours
- **Core Infrastructure**: 5-8 hours
- **Module Development**: Ongoing
- **Testing Framework**: 3-4 hours
- **Documentation**: 2-3 hours
- **Total Initial Setup**: 12-18 hours

---

## Understanding AHK's Import System

### Basic #Include Directive

```ahk
; Method 1: Relative path from current script
#Include MyModule.ahk

; Method 2: Relative path in subdirectory
#Include Utils\StringHelpers.ahk

; Method 3: Absolute path
#Include C:\MyLibrary\Module.ahk

; Method 4: From Lib folder (searches multiple locations)
#Include <MyModule>
```

### Library Search Paths

AutoHotkey v2 searches for `<LibName>` in this order:

1. **Local Lib**: `%A_ScriptDir%\Lib\`
   - Project-specific libraries
   - Highest priority

2. **User Lib**: `%A_MyDocuments%\AutoHotkey\Lib\`
   - User-installed libraries
   - Shared across all user scripts

3. **Standard Lib**: `%A_AhkPath%\..\Lib\`
   - Built-in AutoHotkey libraries
   - Lowest priority (can be overridden)

### Include Behavior

```ahk
; Includes are processed at load time (not runtime)
#Include MyModule.ahk  ; ✓ Processed before script runs

; Cannot conditionally include at runtime
if (condition)
    #Include Module.ahk  ; ✗ Syntax error

; But you can use #Include within classes/functions
class MyClass {
    #Include ClassMethods.ahk  ; ✓ Include class methods
}
```

### Key Limitations to Design Around

1. **Static Includes**: Cannot load modules dynamically at runtime
2. **No Circular Dependencies**: Module A can't include Module B if B includes A
3. **Single Namespace**: All included code shares the global namespace
4. **No Hot-Reload**: Included files aren't reloaded when modified

---

## Design Principles

### 1. Single Responsibility Principle
Each module should do ONE thing well.

```ahk
; ✓ Good: Focused module
; Lib\Json.ahk - Only handles JSON parsing/encoding

; ✗ Bad: Does too much
; Lib\Utils.ahk - JSON, HTTP, File I/O, Math, etc.
```

### 2. Explicit Dependencies
Make dependencies clear and minimal.

```ahk
; ✓ Good: Document dependencies at top
/**
 * StringFormatter.ahk
 * Dependencies: <RegexUtils>, <CharacterSets>
 */
#Include <RegexUtils>
#Include <CharacterSets>
```

### 3. Namespace Protection
Use classes/objects to avoid polluting global namespace.

```ahk
; ✗ Bad: Global functions
FormatString(str) { ... }
ParseString(str) { ... }

; ✓ Good: Namespaced in class
class StringUtils {
    static Format(str) { ... }
    static Parse(str) { ... }
}
```

### 4. Configuration Over Hard-Coding
Allow customization without modifying module code.

```ahk
; ✓ Good: Configurable
class Logger {
    static Config := {
        Level: "INFO",
        OutputPath: A_ScriptDir "\logs",
        MaxFileSize: 10 * 1024 * 1024  ; 10MB
    }
}

; Usage: Customize before using
Logger.Config.Level := "DEBUG"
Logger.Info("Starting...")
```

### 5. Fail-Fast Validation
Validate inputs early and provide clear error messages.

```ahk
class HttpClient {
    static Get(url, options := {}) {
        if !IsSet(url) || url = ""
            throw ValueError("URL is required", -1, url)

        if !RegExMatch(url, "^https?://")
            throw ValueError("URL must start with http:// or https://", -1, url)

        ; ... actual implementation
    }
}
```

### 6. Backward Compatibility
When updating modules, maintain compatibility with existing code.

```ahk
class MyModule {
    ; Version 2.0 - New signature with options object
    static DoSomething(param1, param2 := "", options := {}) {
        ; Backward compatibility: Detect old 3-parameter call
        if IsObject(param2) && !IsSet(options) {
            ; Old: DoSomething(param1, options)
            options := param2
            param2 := ""
        }

        ; ... implementation
    }
}
```

---

## Folder Structure Conventions

### Project Structure

```
MyProject/
├── MyScript.ahk              # Main entry point
├── config.ini                # User configuration
├── README.md                 # Project documentation
│
├── Lib/                      # Local libraries (project-specific)
│   ├── Core/                 # Core functionality modules
│   │   ├── App.ahk          # Application lifecycle
│   │   ├── Config.ahk       # Configuration management
│   │   └── Events.ahk       # Event system
│   │
│   ├── UI/                   # User interface modules
│   │   ├── Components/      # Reusable UI components
│   │   │   ├── Button.ahk
│   │   │   ├── ListView.ahk
│   │   │   └── Dialog.ahk
│   │   ├── Layouts/         # Layout managers
│   │   │   └── GridLayout.ahk
│   │   └── Themes/          # Visual themes
│   │       └── DarkTheme.ahk
│   │
│   ├── Utils/                # Utility modules
│   │   ├── String.ahk       # String manipulation
│   │   ├── File.ahk         # File operations
│   │   ├── Array.ahk        # Array helpers
│   │   └── Object.ahk       # Object helpers
│   │
│   ├── API/                  # External API integrations
│   │   ├── Http.ahk         # HTTP client
│   │   ├── JSON.ahk         # JSON parser
│   │   └── GitHub.ahk       # GitHub API wrapper
│   │
│   └── Plugins/              # Optional plugins (loaded conditionally)
│       ├── PluginManager.ahk
│       ├── LogPlugin.ahk
│       └── DebugPlugin.ahk
│
├── Tests/                    # Test files
│   ├── TestRunner.ahk       # Test framework
│   ├── CoreTests.ahk        # Tests for Core/
│   └── UtilsTests.ahk       # Tests for Utils/
│
├── Examples/                 # Usage examples
│   ├── BasicUsage.ahk
│   └── AdvancedUsage.ahk
│
├── Docs/                     # Additional documentation
│   ├── API.md               # API reference
│   ├── ARCHITECTURE.md      # System architecture
│   └── CONTRIBUTING.md      # Contribution guidelines
│
└── Build/                    # Build artifacts
    ├── dist/                # Compiled executables
    └── package/             # Distribution packages
```

### Module File Template

```ahk
/**
 * ModuleName.ahk
 *
 * Brief description of what this module does.
 *
 * @version 1.0.0
 * @author Your Name
 * @license MIT
 *
 * @requires AutoHotkey v2.0+
 * @requires <DependencyOne>
 * @requires <DependencyTwo>
 *
 * @example
 *   #Include <ModuleName>
 *   result := ModuleName.DoSomething("input")
 */

; Dependencies
#Requires AutoHotkey >=2.0

; Avoid duplicate includes
if IsSet(ModuleName_Included)
    return
ModuleName_Included := true

; Include dependencies
#Include <DependencyOne>
#Include <DependencyTwo>

/**
 * Main module class
 */
class ModuleName {
    ; Module metadata
    static VERSION := "1.0.0"
    static NAME := "ModuleName"

    ; Configuration (can be overridden)
    static Config := {
        Option1: "default",
        Option2: 123
    }

    /**
     * Public method example
     * @param {String} input - Description of parameter
     * @returns {String} Description of return value
     * @throws {ValueError} When input is invalid
     */
    static DoSomething(input) {
        ; Validate input
        if !IsSet(input) || input = ""
            throw ValueError("Input cannot be empty", -1)

        ; Implementation
        return "Result: " input
    }

    /**
     * Private helper method (convention: prefix with _)
     */
    static _HelperMethod() {
        ; Internal implementation
    }
}

; Module initialization (if needed)
ModuleName._Initialize()
```

---

## Module Patterns & Types

### Pattern 1: Static Utility Class

Best for: Stateless helper functions

```ahk
/**
 * StringUtils.ahk - String manipulation utilities
 */
class StringUtils {
    /**
     * Truncate string to max length with ellipsis
     */
    static Truncate(str, maxLen, ellipsis := "...") {
        if StrLen(str) <= maxLen
            return str
        return SubStr(str, 1, maxLen - StrLen(ellipsis)) ellipsis
    }

    /**
     * Convert string to title case
     */
    static ToTitleCase(str) {
        return RegExReplace(str, "\b(\w)", (m) => StrUpper(m[1]))
    }

    /**
     * Remove all whitespace
     */
    static StripWhitespace(str) {
        return RegExReplace(str, "\s+", "")
    }
}

; Usage:
; #Include <StringUtils>
; result := StringUtils.Truncate("Long text here", 10)
```

### Pattern 2: Singleton Service

Best for: Stateful services (logger, config, cache)

```ahk
/**
 * Logger.ahk - Application logging service
 */
class Logger {
    static _instance := ""
    static _logFile := ""
    static _level := "INFO"

    /**
     * Get singleton instance
     */
    static Instance {
        get {
            if !Logger._instance
                Logger._instance := Logger.New()
            return Logger._instance
        }
    }

    /**
     * Private constructor
     */
    __New() {
        this._logFile := A_ScriptDir "\app.log"
    }

    /**
     * Set log level
     */
    static SetLevel(level) {
        Logger._level := level
    }

    /**
     * Log info message
     */
    static Info(message) {
        Logger.Instance._Write("INFO", message)
    }

    /**
     * Log error message
     */
    static Error(message) {
        Logger.Instance._Write("ERROR", message)
    }

    /**
     * Internal write method
     */
    _Write(level, message) {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        line := Format("[{1}] {2}: {3}`n", timestamp, level, message)
        FileAppend(line, this._logFile)
    }
}

; Usage:
; Logger.Info("Application started")
```

### Pattern 3: Factory

Best for: Creating different variations of objects

```ahk
/**
 * DialogFactory.ahk - Create different types of dialogs
 */
class DialogFactory {
    /**
     * Create message dialog
     */
    static CreateMessage(title, message, buttons := "OK") {
        return MessageDialog(title, message, buttons)
    }

    /**
     * Create input dialog
     */
    static CreateInput(title, prompt, default := "") {
        return InputDialog(title, prompt, default)
    }

    /**
     * Create file picker dialog
     */
    static CreateFilePicker(title, filter := "*.*") {
        return FilePickerDialog(title, filter)
    }
}

class MessageDialog {
    __New(title, message, buttons) {
        this.title := title
        this.message := message
        this.buttons := buttons
    }

    Show() {
        return MsgBox(this.message, this.title, this.buttons)
    }
}

class InputDialog {
    __New(title, prompt, default) {
        this.title := title
        this.prompt := prompt
        this.default := default
    }

    Show() {
        ib := InputBox(this.prompt, this.title, , this.default)
        if ib.Result = "Cancel"
            return ""
        return ib.Value
    }
}

; Usage:
; dialog := DialogFactory.CreateMessage("Hello", "World!")
; dialog.Show()
```

### Pattern 4: Plugin System

Best for: Optional, loadable extensions

```ahk
/**
 * PluginManager.ahk - Manage loadable plugins
 */
class PluginManager {
    static _plugins := Map()
    static _hooks := Map()

    /**
     * Register a plugin
     */
    static Register(name, pluginClass) {
        if PluginManager._plugins.Has(name)
            throw ValueError("Plugin already registered: " name)

        ; Validate plugin implements required interface
        if !pluginClass.HasMethod("OnLoad")
            throw ValueError("Plugin must implement OnLoad() method")

        PluginManager._plugins[name] := pluginClass
        pluginClass.OnLoad()
    }

    /**
     * Get plugin by name
     */
    static Get(name) {
        if !PluginManager._plugins.Has(name)
            throw ValueError("Plugin not found: " name)
        return PluginManager._plugins[name]
    }

    /**
     * Register hook listener
     */
    static RegisterHook(hookName, callback) {
        if !PluginManager._hooks.Has(hookName)
            PluginManager._hooks[hookName] := []
        PluginManager._hooks[hookName].Push(callback)
    }

    /**
     * Trigger hook
     */
    static TriggerHook(hookName, data := "") {
        if !PluginManager._hooks.Has(hookName)
            return

        for callback in PluginManager._hooks[hookName] {
            callback(data)
        }
    }
}

/**
 * Base plugin class
 */
class Plugin {
    static NAME := "BasePlugin"
    static VERSION := "1.0.0"

    static OnLoad() {
        ; Override in subclass
    }

    static OnUnload() {
        ; Override in subclass
    }
}

; Example plugin:
class LogPlugin extends Plugin {
    static NAME := "LogPlugin"

    static OnLoad() {
        PluginManager.RegisterHook("app.start", (*) => this.LogStart())
        PluginManager.RegisterHook("app.error", (err) => this.LogError(err))
    }

    static LogStart() {
        FileAppend("App started at " A_Now "`n", "plugin.log")
    }

    static LogError(err) {
        FileAppend("Error: " err "`n", "plugin.log")
    }
}

; Usage in main script:
; #Include <PluginManager>
; #Include <Plugins\LogPlugin>
; PluginManager.Register("log", LogPlugin)
; PluginManager.TriggerHook("app.start")
```

### Pattern 5: Event Bus

Best for: Decoupled communication between modules

```ahk
/**
 * EventBus.ahk - Centralized event system
 */
class EventBus {
    static _listeners := Map()

    /**
     * Subscribe to event
     */
    static On(eventName, callback, priority := 0) {
        if !EventBus._listeners.Has(eventName)
            EventBus._listeners[eventName] := []

        EventBus._listeners[eventName].Push({
            callback: callback,
            priority: priority
        })

        ; Sort by priority (higher = earlier)
        EventBus._SortListeners(eventName)
    }

    /**
     * Unsubscribe from event
     */
    static Off(eventName, callback) {
        if !EventBus._listeners.Has(eventName)
            return

        listeners := EventBus._listeners[eventName]
        for i, listener in listeners {
            if listener.callback = callback {
                listeners.RemoveAt(i)
                break
            }
        }
    }

    /**
     * Emit event
     */
    static Emit(eventName, data := "") {
        if !EventBus._listeners.Has(eventName)
            return

        for listener in EventBus._listeners[eventName] {
            listener.callback(data)
        }
    }

    /**
     * Emit event and wait for first return value
     */
    static EmitWithResult(eventName, data := "") {
        if !EventBus._listeners.Has(eventName)
            return ""

        for listener in EventBus._listeners[eventName] {
            result := listener.callback(data)
            if IsSet(result) && result != ""
                return result
        }
        return ""
    }

    /**
     * Sort listeners by priority
     */
    static _SortListeners(eventName) {
        listeners := EventBus._listeners[eventName]

        ; Bubble sort by priority (descending)
        n := listeners.Length
        loop n - 1 {
            i := A_Index
            loop n - i {
                j := A_Index
                if listeners[j].priority < listeners[j + 1].priority {
                    temp := listeners[j]
                    listeners[j] := listeners[j + 1]
                    listeners[j + 1] := temp
                }
            }
        }
    }
}

; Usage:
; #Include <EventBus>
;
; EventBus.On("user.login", (user) => MsgBox("Welcome " user.name))
; EventBus.On("user.login", (user) => Logger.Info("User logged in: " user.name))
;
; EventBus.Emit("user.login", {name: "John", id: 123})
```

### Pattern 6: Repository/Data Access

Best for: Data storage and retrieval abstraction

```ahk
/**
 * IniRepository.ahk - INI file data access
 */
class IniRepository {
    _filePath := ""

    __New(filePath) {
        this._filePath := filePath

        ; Create file if it doesn't exist
        if !FileExist(filePath)
            FileAppend("", filePath)
    }

    /**
     * Get value from section
     */
    Get(section, key, default := "") {
        value := IniRead(this._filePath, section, key, "§§NOTFOUND§§")
        return (value = "§§NOTFOUND§§") ? default : value
    }

    /**
     * Set value in section
     */
    Set(section, key, value) {
        IniWrite(value, this._filePath, section, key)
    }

    /**
     * Delete key from section
     */
    Delete(section, key) {
        IniDelete(this._filePath, section, key)
    }

    /**
     * Get all keys in section as Map
     */
    GetSection(section) {
        result := Map()
        content := IniRead(this._filePath, section)

        loop parse content, "`n", "`r" {
            if A_LoopField = ""
                continue

            parts := StrSplit(A_LoopField, "=", , 2)
            if parts.Length = 2
                result[parts[1]] := parts[2]
        }

        return result
    }

    /**
     * Check if section exists
     */
    HasSection(section) {
        content := IniRead(this._filePath, section, , "§§NOTFOUND§§")
        return content != "§§NOTFOUND§§"
    }
}

; Usage:
; config := IniRepository(A_ScriptDir "\settings.ini")
; config.Set("General", "Theme", "Dark")
; theme := config.Get("General", "Theme", "Light")
```

---

## Dependency Management

### Approach 1: Manual Documentation

Simple but requires discipline.

```ahk
/**
 * MyModule.ahk
 *
 * @requires <HttpClient>  version >= 1.2.0
 * @requires <JSON>        version >= 2.0.0
 */
#Include <HttpClient>
#Include <JSON>

class MyModule {
    static VERSION := "1.0.0"
    static DEPENDENCIES := Map(
        "HttpClient", ">=1.2.0",
        "JSON", ">=2.0.0"
    )

    static _CheckDependencies() {
        for name, version in MyModule.DEPENDENCIES {
            if !IsSet(%name%)
                throw Error("Missing dependency: " name)

            ; Check version if module provides it
            if %name%.HasOwnProp("VERSION") {
                if !MyModule._VersionMatch(%name%.VERSION, version)
                    throw Error(Format("Dependency version mismatch: {1} {2} required, got {3}",
                        name, version, %name%.VERSION))
            }
        }
    }

    static _VersionMatch(actual, required) {
        ; Simple version check (supports >=, >, =, <, <=)
        ; Example: _VersionMatch("1.2.0", ">=1.0.0") returns true

        if SubStr(required, 1, 2) = ">=" {
            return MyModule._CompareVersions(actual, SubStr(required, 3)) >= 0
        } else if SubStr(required, 1, 1) = ">" {
            return MyModule._CompareVersions(actual, SubStr(required, 2)) > 0
        } else if SubStr(required, 1, 2) = "<=" {
            return MyModule._CompareVersions(actual, SubStr(required, 3)) <= 0
        } else if SubStr(required, 1, 1) = "<" {
            return MyModule._CompareVersions(actual, SubStr(required, 2)) < 0
        } else if SubStr(required, 1, 1) = "=" {
            return actual = SubStr(required, 2)
        }

        return actual = required
    }

    static _CompareVersions(v1, v2) {
        ; Compare versions (e.g., "1.2.3" vs "1.3.0")
        ; Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2

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
}

; Initialize and check dependencies
MyModule._CheckDependencies()
```

### Approach 2: Module Registry

Centralized registry for managing modules.

```ahk
/**
 * ModuleRegistry.ahk - Central module management
 */
class ModuleRegistry {
    static _modules := Map()
    static _loadOrder := []

    /**
     * Register module
     */
    static Register(name, version, moduleClass) {
        if ModuleRegistry._modules.Has(name)
            throw ValueError("Module already registered: " name)

        ModuleRegistry._modules[name] := {
            name: name,
            version: version,
            class: moduleClass,
            loaded: false
        }
    }

    /**
     * Get module
     */
    static Get(name, requiredVersion := "") {
        if !ModuleRegistry._modules.Has(name)
            throw ValueError("Module not found: " name)

        module := ModuleRegistry._modules[name]

        ; Check version if specified
        if requiredVersion != "" && module.version != requiredVersion {
            throw ValueError(Format("Version mismatch: {1} requires {2}, got {3}",
                name, requiredVersion, module.version))
        }

        ; Load module if not loaded
        if !module.loaded {
            ModuleRegistry._Load(module)
        }

        return module.class
    }

    /**
     * Load module and its dependencies
     */
    static _Load(module) {
        ; Check if module has dependencies
        if module.class.HasOwnProp("DEPENDENCIES") {
            for depName, depVersion in module.class.DEPENDENCIES {
                ; Recursively load dependency
                ModuleRegistry.Get(depName, depVersion)
            }
        }

        ; Initialize module if it has Init method
        if module.class.HasMethod("Init")
            module.class.Init()

        module.loaded := true
        ModuleRegistry._loadOrder.Push(module.name)
    }

    /**
     * List all registered modules
     */
    static List() {
        modules := []
        for name, module in ModuleRegistry._modules {
            modules.Push(Format("{1} v{2} [{3}]",
                name, module.version, module.loaded ? "loaded" : "not loaded"))
        }
        return modules
    }
}

; Usage in modules:
; At end of each module file:
; ModuleRegistry.Register("MyModule", "1.0.0", MyModule)

; In main script:
; #Include <ModuleRegistry>
; #Include <AllModules>  ; Includes all module files
;
; MyMod := ModuleRegistry.Get("MyModule", ">=1.0.0")
; result := MyMod.DoSomething()
```

### Approach 3: Lazy Loading

Load modules only when needed.

```ahk
/**
 * LazyLoader.ahk - Load modules on demand
 */
class LazyLoader {
    static _cache := Map()
    static _paths := Map()

    /**
     * Register module path
     */
    static RegisterPath(name, filePath) {
        LazyLoader._paths[name] := filePath
    }

    /**
     * Get module (loads if not cached)
     */
    static Get(name) {
        ; Return from cache if already loaded
        if LazyLoader._cache.Has(name)
            return LazyLoader._cache[name]

        ; Check if path is registered
        if !LazyLoader._paths.Has(name)
            throw ValueError("Module path not registered: " name)

        ; Load module
        filePath := LazyLoader._paths[name]
        if !FileExist(filePath)
            throw ValueError("Module file not found: " filePath)

        ; Include and instantiate
        #Include %filePath%

        ; Assume module exports class with same name
        moduleClass := %name%

        ; Cache and return
        LazyLoader._cache[name] := moduleClass
        return moduleClass
    }

    /**
     * Clear cache
     */
    static Clear() {
        LazyLoader._cache := Map()
    }
}

; Setup in main script:
LazyLoader.RegisterPath("HttpClient", A_ScriptDir "\Lib\HttpClient.ahk")
LazyLoader.RegisterPath("JSON", A_ScriptDir "\Lib\JSON.ahk")

; Use when needed:
Http := LazyLoader.Get("HttpClient")
response := Http.Get("https://api.example.com/data")
```

---

## Versioning & Compatibility

### Semantic Versioning

Follow SemVer: `MAJOR.MINOR.PATCH`

```ahk
class MyModule {
    static VERSION := "2.1.3"

    ; MAJOR version: Breaking changes (incompatible API changes)
    ; Examples:
    ;   - Removing a public method
    ;   - Changing method signatures
    ;   - Changing return types

    ; MINOR version: New features (backward-compatible)
    ; Examples:
    ;   - Adding new methods
    ;   - Adding optional parameters
    ;   - Adding new classes

    ; PATCH version: Bug fixes (backward-compatible)
    ; Examples:
    ;   - Fixing bugs
    ;   - Performance improvements
    ;   - Documentation updates
}
```

### Deprecation Strategy

```ahk
class MyModule {
    static VERSION := "2.0.0"

    /**
     * Old method (deprecated in v2.0.0, will be removed in v3.0.0)
     * @deprecated Use NewMethod() instead
     */
    static OldMethod(param) {
        ; Show deprecation warning
        static warned := false
        if !warned {
            MsgBox("Warning: MyModule.OldMethod() is deprecated. Use NewMethod() instead.", "Deprecation Warning", "Icon!")
            warned := true
        }

        ; Delegate to new method
        return MyModule.NewMethod(param)
    }

    /**
     * New method (added in v2.0.0)
     */
    static NewMethod(param) {
        ; New implementation
        return param
    }
}
```

### Compatibility Layer

```ahk
/**
 * Compat.ahk - Maintain compatibility across AHK versions
 */
class Compat {
    /**
     * Check AHK version
     */
    static IsV2() => SubStr(A_AhkVersion, 1, 1) = "2"

    /**
     * Polyfill for Map (v1 doesn't have it)
     */
    static CreateMap() {
        if Compat.IsV2()
            return Map()
        else
            return {}  ; Use object in v1
    }

    /**
     * Universal get from Map/Object
     */
    static MapGet(container, key, default := "") {
        if Compat.IsV2() {
            return container.Has(key) ? container[key] : default
        } else {
            return container.HasKey(key) ? container[key] : default
        }
    }
}
```

---

## Testing Strategy

### Simple Test Framework

```ahk
/**
 * TestFramework.ahk - Lightweight testing framework
 */
class TestFramework {
    static _tests := []
    static _results := []

    /**
     * Register test
     */
    static Test(name, testFunc) {
        TestFramework._tests.Push({
            name: name,
            func: testFunc
        })
    }

    /**
     * Run all tests
     */
    static RunAll() {
        TestFramework._results := []
        passed := 0
        failed := 0

        OutputDebug("=== Running Tests ===`n")

        for test in TestFramework._tests {
            try {
                test.func()
                TestFramework._results.Push({
                    name: test.name,
                    passed: true,
                    error: ""
                })
                passed++
                OutputDebug("✓ " test.name "`n")
            } catch as err {
                TestFramework._results.Push({
                    name: test.name,
                    passed: false,
                    error: err.Message
                })
                failed++
                OutputDebug("✗ " test.name " - " err.Message "`n")
            }
        }

        OutputDebug(Format("`n=== Results: {1} passed, {2} failed ===`n", passed, failed))

        return {passed: passed, failed: failed, results: TestFramework._results}
    }

    /**
     * Assertions
     */
    static Assert(condition, message := "Assertion failed") {
        if !condition
            throw Error(message)
    }

    static AssertEqual(actual, expected, message := "") {
        if actual != expected {
            msg := message != "" ? message : Format("Expected {1}, got {2}", expected, actual)
            throw Error(msg)
        }
    }

    static AssertNotEqual(actual, notExpected, message := "") {
        if actual = notExpected {
            msg := message != "" ? message : Format("Expected not {1}, but got it", notExpected)
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
}

; Example test file:
/**
 * StringUtilsTests.ahk
 */
#Include <TestFramework>
#Include <StringUtils>

TestFramework.Test("Truncate - Normal case", (*) {
    result := StringUtils.Truncate("Hello World", 8)
    TestFramework.AssertEqual(result, "Hello...", "Should truncate with ellipsis")
})

TestFramework.Test("Truncate - No truncation needed", (*) {
    result := StringUtils.Truncate("Hi", 10)
    TestFramework.AssertEqual(result, "Hi", "Should not truncate short strings")
})

TestFramework.Test("ToTitleCase", (*) {
    result := StringUtils.ToTitleCase("hello world")
    TestFramework.AssertEqual(result, "Hello World")
})

; Run tests
if A_ScriptName = "StringUtilsTests.ahk" {
    results := TestFramework.RunAll()
    ExitApp(results.failed > 0 ? 1 : 0)
}
```

### Integration Testing

```ahk
/**
 * IntegrationTests.ahk - Test module interactions
 */
#Include <TestFramework>
#Include <HttpClient>
#Include <JSON>
#Include <Logger>

TestFramework.Test("HTTP + JSON Integration", (*) {
    ; Test that HTTP client and JSON parser work together
    response := HttpClient.Get("https://jsonplaceholder.typicode.com/todos/1")
    data := JSON.Parse(response.body)

    TestFramework.Assert(IsObject(data), "Should parse JSON")
    TestFramework.AssertEqual(data.id, 1, "Should have correct ID")
})

TestFramework.Test("Logger + File System Integration", (*) {
    ; Test logger writes to file
    testLog := A_Temp "\test.log"

    if FileExist(testLog)
        FileDelete(testLog)

    Logger.SetFile(testLog)
    Logger.Info("Test message")

    TestFramework.Assert(FileExist(testLog), "Log file should exist")

    content := FileRead(testLog)
    TestFramework.Assert(InStr(content, "Test message"), "Log should contain message")

    ; Cleanup
    FileDelete(testLog)
})

TestFramework.RunAll()
```

---

## Documentation Standards

### Module Documentation Template

```ahk
/**
 * ModuleName.ahk
 *
 * ## Description
 * Detailed description of what this module does and why it exists.
 *
 * ## Features
 * - Feature 1
 * - Feature 2
 * - Feature 3
 *
 * ## Installation
 * 1. Copy ModuleName.ahk to your Lib folder
 * 2. Include in your script: #Include <ModuleName>
 *
 * ## Quick Start
 * ```ahk
 * #Include <ModuleName>
 * result := ModuleName.DoSomething("input")
 * ```
 *
 * ## API Reference
 * See inline documentation below
 *
 * ## Dependencies
 * - AutoHotkey v2.0+
 * - DependencyOne v1.2+
 * - DependencyTwo v2.0+
 *
 * ## Examples
 * See Examples/ModuleName/ folder
 *
 * ## License
 * MIT License - See LICENSE file
 *
 * ## Changelog
 * - v1.0.0 (2024-01-01): Initial release
 *
 * @version 1.0.0
 * @author Your Name <your.email@example.com>
 * @link https://github.com/yourname/modulename
 */
```

### Method Documentation

```ahk
/**
 * Process a string with various options
 *
 * This method takes a string and processes it according to the
 * provided options. It supports multiple processing modes.
 *
 * @param {String} input - The input string to process
 * @param {Object} options - Processing options
 * @param {String} options.mode - Processing mode: "upper", "lower", "title"
 * @param {Boolean} options.trim - Whether to trim whitespace (default: true)
 * @param {Integer} options.maxLength - Maximum length (0 = unlimited)
 *
 * @returns {String} The processed string
 *
 * @throws {ValueError} If input is empty
 * @throws {ValueError} If mode is invalid
 *
 * @example
 *   ; Basic usage
 *   result := StringUtils.Process("hello", {mode: "upper"})
 *   ; Returns: "HELLO"
 *
 * @example
 *   ; With multiple options
 *   result := StringUtils.Process("  Hello World  ", {
 *       mode: "title",
 *       trim: true,
 *       maxLength: 10
 *   })
 *   ; Returns: "Hello W..."
 *
 * @since 1.0.0
 */
static Process(input, options := {}) {
    ; Implementation
}
```

### README Template

```markdown
# ModuleName

Brief one-line description.

## Features

- Feature 1
- Feature 2
- Feature 3

## Installation

### Method 1: Copy to Lib folder

1. Download `ModuleName.ahk`
2. Copy to `%A_MyDocuments%\AutoHotkey\Lib\`
3. Include in your script: `#Include <ModuleName>`

### Method 2: Direct include

1. Download `ModuleName.ahk`
2. Place in your project folder
3. Include: `#Include ModuleName.ahk`

## Quick Start

```ahk
#Include <ModuleName>

; Basic usage
result := ModuleName.DoSomething("input")
MsgBox(result)
```

## API Reference

### Methods

#### `DoSomething(input, options := {})`

Description of what it does.

**Parameters:**
- `input` (String): Description
- `options` (Object): Optional configuration

**Returns:** Description of return value

**Example:**
```ahk
result := ModuleName.DoSomething("test")
```

## Examples

See `Examples/` folder for complete examples.

## Dependencies

- AutoHotkey v2.0+
- DependencyOne v1.2+ - [Link](https://example.com)

## Testing

Run tests with:
```ahk
AutoHotkey Tests\ModuleNameTests.ahk
```

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - See LICENSE file

## Changelog

### v1.0.0 (2024-01-01)
- Initial release
```

---

## Distribution Methods

### Method 1: Single File

Easiest to distribute, harder to maintain.

```ahk
; Package everything in one file
; ModuleName_Standalone.ahk

; Inline all dependencies
class Dependency1 { ... }
class Dependency2 { ... }

; Main module
class ModuleName {
    ; Uses Dependency1 and Dependency2
}
```

### Method 2: Zip Archive

```
ModuleName_v1.0.0.zip
├── README.md
├── LICENSE
├── Lib/
│   ├── ModuleName.ahk
│   ├── Dependency1.ahk
│   └── Dependency2.ahk
├── Examples/
│   ├── Basic.ahk
│   └── Advanced.ahk
└── INSTALL.md
```

**INSTALL.md:**
```markdown
# Installation Instructions

1. Extract zip to temporary location
2. Copy contents of `Lib/` to `%A_MyDocuments%\AutoHotkey\Lib\`
3. Test installation by running `Examples/Basic.ahk`
```

### Method 3: Git Repository

```
https://github.com/username/ahk-modulename

Clone or download, then:
1. git clone https://github.com/username/ahk-modulename
2. Copy Lib/*.ahk to your AutoHotkey Lib folder
```

### Method 4: Package Manager (Future)

Concept for an AHK package manager:

```ahk
; ahk-pm.ahk - Hypothetical package manager

#Include <PackageManager>

; Install package
PM.Install("username/modulename")

; Update package
PM.Update("username/modulename")

; Remove package
PM.Remove("username/modulename")

; List installed
PM.List()
```

---

## Implementation Examples

### Complete Example 1: Config System

```ahk
/**
 * Config.ahk - Configuration management system
 */
class Config {
    static VERSION := "1.0.0"
    static _data := Map()
    static _file := ""
    static _loaded := false

    /**
     * Load configuration from file
     */
    static Load(filePath := "") {
        if filePath = ""
            filePath := A_ScriptDir "\config.ini"

        Config._file := filePath

        if !FileExist(filePath) {
            Config._LoadDefaults()
            Config.Save()
            return
        }

        ; Read all sections
        sections := ["General", "UI", "Advanced"]
        for section in sections {
            data := IniRead(filePath, section)
            if data = ""
                continue

            loop parse data, "`n", "`r" {
                if A_LoopField = ""
                    continue

                parts := StrSplit(A_LoopField, "=", , 2)
                if parts.Length = 2 {
                    key := section "." parts[1]
                    Config._data[key] := Config._ParseValue(parts[2])
                }
            }
        }

        Config._loaded := true
    }

    /**
     * Get configuration value
     */
    static Get(key, default := "") {
        if !Config._loaded
            Config.Load()

        return Config._data.Has(key) ? Config._data[key] : default
    }

    /**
     * Set configuration value
     */
    static Set(key, value) {
        Config._data[key] := value
    }

    /**
     * Save configuration to file
     */
    static Save() {
        if Config._file = ""
            throw Error("No config file specified")

        ; Group by section
        sections := Map()
        for key, value in Config._data {
            parts := StrSplit(key, ".", , 2)
            section := parts[1]
            keyName := parts[2]

            if !sections.Has(section)
                sections[section] := []
            sections[section].Push(keyName "=" Config._FormatValue(value))
        }

        ; Write to file
        for section, lines in sections {
            for line in lines {
                parts := StrSplit(line, "=", , 2)
                IniWrite(parts[2], Config._file, section, parts[1])
            }
        }
    }

    /**
     * Load default configuration
     */
    static _LoadDefaults() {
        Config._data := Map(
            "General.AppName", "MyApp",
            "General.Version", "1.0.0",
            "UI.Theme", "Light",
            "UI.FontSize", 10,
            "Advanced.LogLevel", "INFO",
            "Advanced.AutoUpdate", true
        )
    }

    /**
     * Parse string value to correct type
     */
    static _ParseValue(str) {
        ; Boolean
        if str = "true"
            return true
        if str = "false"
            return false

        ; Number
        if IsNumber(str)
            return Number(str)

        ; String
        return str
    }

    /**
     * Format value for INI file
     */
    static _FormatValue(value) {
        if Type(value) = "Integer" || Type(value) = "Float"
            return String(value)
        if Type(value) = "String"
            return value

        ; Boolean
        return value ? "true" : "false"
    }
}

; Auto-load when included
Config.Load()
```

### Complete Example 2: HTTP Client

```ahk
/**
 * HttpClient.ahk - Simple HTTP client module
 */
class HttpClient {
    static VERSION := "1.0.0"
    static TIMEOUT := 30000  ; 30 seconds
    static USER_AGENT := "AHK-HttpClient/1.0"

    /**
     * GET request
     */
    static Get(url, headers := Map()) {
        return HttpClient._Request("GET", url, "", headers)
    }

    /**
     * POST request
     */
    static Post(url, body := "", headers := Map()) {
        return HttpClient._Request("POST", url, body, headers)
    }

    /**
     * PUT request
     */
    static Put(url, body := "", headers := Map()) {
        return HttpClient._Request("PUT", url, body, headers)
    }

    /**
     * DELETE request
     */
    static Delete(url, headers := Map()) {
        return HttpClient._Request("DELETE", url, "", headers)
    }

    /**
     * Make HTTP request
     */
    static _Request(method, url, body, headers) {
        ; Validate URL
        if !RegExMatch(url, "^https?://")
            throw ValueError("Invalid URL: " url)

        ; Create WinHTTP object
        whr := ComObject("WinHttp.WinHttpRequest.5.1")

        ; Open request
        whr.Open(method, url, true)

        ; Set timeout
        whr.SetTimeouts(0, 5000, 10000, HttpClient.TIMEOUT)

        ; Set headers
        whr.SetRequestHeader("User-Agent", HttpClient.USER_AGENT)
        for key, value in headers {
            whr.SetRequestHeader(key, value)
        }

        ; Send request
        try {
            whr.Send(body)
            whr.WaitForResponse()
        } catch as err {
            throw Error("HTTP request failed: " err.Message)
        }

        ; Parse response
        response := {
            status: whr.Status,
            statusText: whr.StatusText,
            body: whr.ResponseText,
            headers: Map()
        }

        ; Parse response headers
        headerText := whr.GetAllResponseHeaders()
        loop parse headerText, "`n", "`r" {
            if A_LoopField = ""
                continue

            parts := StrSplit(A_LoopField, ":", , 2)
            if parts.Length = 2
                response.headers[Trim(parts[1])] := Trim(parts[2])
        }

        return response
    }

    /**
     * Download file
     */
    static Download(url, outputPath, onProgress := "") {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", url, true)
        whr.Send()
        whr.WaitForResponse()

        ; Get response as binary
        responseBody := whr.ResponseBody

        ; Write to file
        file := FileOpen(outputPath, "w")
        file.RawWrite(responseBody)
        file.Close()

        return true
    }
}
```

### Complete Example 3: Plugin System Implementation

See Pattern 4 earlier for the PluginManager. Here's a complete usage example:

```ahk
/**
 * Main.ahk - Application with plugin system
 */
#Include <PluginManager>

; Define application hooks
class App {
    static VERSION := "1.0.0"

    static Start() {
        ; Trigger startup hook
        PluginManager.TriggerHook("app.start")

        MsgBox("App started")

        ; Do something that might error
        try {
            ; ... app logic
        } catch as err {
            PluginManager.TriggerHook("app.error", err.Message)
        }

        ; Trigger shutdown hook
        PluginManager.TriggerHook("app.shutdown")
    }
}

; Load plugins
#Include Plugins\LogPlugin.ahk
#Include Plugins\ConfigPlugin.ahk
#Include Plugins\UIPlugin.ahk

; Register plugins
PluginManager.Register("log", LogPlugin)
PluginManager.Register("config", ConfigPlugin)
PluginManager.Register("ui", UIPlugin)

; Start app
App.Start()
```

---

## Best Practices

### 1. Keep Modules Small and Focused
- ✓ One module = one responsibility
- ✓ Aim for < 500 lines per module
- ✗ Avoid "god classes" that do everything

### 2. Use Clear Naming Conventions
```ahk
; ✓ Good names
StringUtils.ahk
HttpClient.ahk
ConfigManager.ahk

; ✗ Bad names
Stuff.ahk
Helper.ahk
Util.ahk
```

### 3. Document Everything
- Every module needs a header comment
- Every public method needs documentation
- Include examples in documentation

### 4. Validate Inputs Early
```ahk
static ProcessData(data) {
    ; Validate first
    if !IsObject(data)
        throw TypeError("data must be an object")
    if !data.HasOwnProp("id")
        throw ValueError("data must have 'id' property")

    ; Then process
    return "Processed: " data.id
}
```

### 5. Use Consistent Error Handling
```ahk
; Define error codes
class ErrorCodes {
    static INVALID_INPUT := 1000
    static NOT_FOUND := 1001
    static NETWORK_ERROR := 1002
}

; Throw structured errors
throw Error("Resource not found", ErrorCodes.NOT_FOUND, resource)
```

### 6. Provide Configuration Options
```ahk
class MyModule {
    static Config := {
        Option1: "default",
        Option2: 123
    }
}

; Users can override:
MyModule.Config.Option1 := "custom"
```

### 7. Write Tests
- Test public methods
- Test edge cases
- Test error conditions

### 8. Version Everything
```ahk
class MyModule {
    static VERSION := "1.2.3"
}
```

### 9. Avoid Global State When Possible
```ahk
; ✗ Bad: Global state
global gCounter := 0

IncreaseCounter() {
    global gCounter
    gCounter++
}

; ✓ Good: Encapsulated state
class Counter {
    _value := 0

    Increase() => ++this._value
    Get() => this._value
}
```

### 10. Use Dependency Injection
```ahk
; ✗ Bad: Hard dependency
class UserService {
    static GetUser(id) {
        return Database.Query("SELECT * FROM users WHERE id = " id)
    }
}

; ✓ Good: Inject dependency
class UserService {
    __New(database) {
        this.db := database
    }

    GetUser(id) {
        return this.db.Query("SELECT * FROM users WHERE id = " id)
    }
}

; Usage:
db := Database.Connect("mydb.sqlite")
userService := UserService(db)
```

---

## Summary & Next Steps

### Summary

You now have a comprehensive plan for creating a modular system in AutoHotkey v2:

1. **Understanding**: Know how #Include works and Lib search paths
2. **Design**: Follow solid principles (SRP, namespacing, validation)
3. **Structure**: Organize with consistent folder structure
4. **Patterns**: Use appropriate patterns (singleton, factory, plugin, etc.)
5. **Dependencies**: Manage with registry or lazy loading
6. **Testing**: Write tests with simple framework
7. **Documentation**: Document thoroughly with standards
8. **Distribution**: Package for easy sharing

### Next Steps

1. **Start Small**
   - Create one utility module (e.g., StringUtils)
   - Test it in a simple script
   - Refine based on usage

2. **Build Core Infrastructure**
   - Implement ModuleRegistry or PluginManager
   - Create TestFramework
   - Set up folder structure

3. **Develop Key Modules**
   - Config management
   - HTTP client
   - Logger
   - UI components

4. **Document Everything**
   - Write README for each module
   - Create examples
   - Document dependencies

5. **Test Thoroughly**
   - Write unit tests
   - Write integration tests
   - Test in real projects

6. **Share & Iterate**
   - Publish on GitHub
   - Get feedback
   - Improve based on usage

### Resources

- **AutoHotkey v2 Docs**: https://www.autohotkey.com/docs/v2/
- **Example Libraries**: Study existing AHK libraries on GitHub
- **Design Patterns**: Apply classic patterns to AHK context
- **SemVer**: https://semver.org/

### Success Metrics

Your modular system is successful when:
- ✓ Modules are easy to install and use
- ✓ Dependencies are clear and manageable
- ✓ Code is reusable across projects
- ✓ Tests pass consistently
- ✓ Documentation is clear
- ✓ Other developers can contribute

---

**Ready to build your modular AutoHotkey system!** 🚀
