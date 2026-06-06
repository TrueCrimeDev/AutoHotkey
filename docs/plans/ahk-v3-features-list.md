# AutoHotkey v3 Features List

A comprehensive features list for AutoHotkey v3 — informed by v2's architecture, community pain points, the evolving v2.1 alpha work, and this project's debugger/AI integration experience.

---

## 1. Module System & Package Management

### 1.1 Native Module System
v2.1 alpha introduces `#Module`, `Import`, and `Export`. v3 should mature this into a full module system:

- **Namespaced imports** — `Import { Gui, Menu } from "std/ui"` with clear scoping rules
- **Circular dependency resolution** — handled at load time with clear error messages
- **Module-level variables** — private by default, explicitly exported
- **Conditional imports** — `Import "winapi/com" if A_OSVersion >= "10"`
- **Lazy imports** — defer loading until first use for faster startup
- **Re-exports** — `Export * from "submodule"` for building facade modules

### 1.2 Official Package Manager
- **Built-in CLI** — `ahk install <package>`, `ahk update`, `ahk publish`
- **Central registry** — official package index (like npm/PyPI) with version pinning
- **Lock files** — deterministic dependency resolution (`ahk.lock`)
- **Local packages** — `ahk install ./libs/my-utility` for monorepo workflows
- **GUI frontend** — since many AHK users are not developers, provide a graphical package browser
- **Semantic versioning enforcement** — packages declare compatibility ranges

### 1.3 Standard Library Reorganization
Break the monolithic built-in function set into importable standard library modules:

| Module | Contents |
|--------|----------|
| `std/string` | String manipulation, regex |
| `std/file` | File I/O, path utilities |
| `std/gui` | GUI controls, menus, tray |
| `std/win` | Window management, WinTitle |
| `std/input` | Hotkeys, hotstrings, input hooks |
| `std/net` | HTTP client, WebSocket, TCP/UDP |
| `std/json` | JSON parse/stringify (currently requires libraries) |
| `std/com` | COM/ActiveX automation |
| `std/dll` | DllCall, struct definitions |
| `std/process` | Process management, Run/RunWait |
| `std/registry` | Registry read/write |
| `std/crypto` | Hashing, HMAC, basic encryption |
| `std/datetime` | Date/time parsing, formatting, arithmetic |

---

## 2. Type System

### 2.1 Optional Type Annotations
A gradual typing approach — valid AHK v3 with or without type annotations:

```autohotkey
; Untyped (still works)
Add(a, b) => a + b

; Typed (enables compile-time checks and better tooling)
Add(a: Number, b: Number) -> Number => a + b

; Complex types
ProcessFiles(paths: Array<String>, callback: (String) -> Bool) -> Number {
    count := 0
    for path in paths {
        if callback(path)
            count++
    }
    return count
}
```

### 2.2 Struct Types (Extending v2.1 Work)
v2.1 adds typed properties. v3 should make structs first-class:

```autohotkey
struct POINT {
    x: Int32
    y: Int32
}

struct RECT {
    left: Int32
    top: Int32
    right: Int32
    bottom: Int32

    Width => this.right - this.left
    Height => this.bottom - this.top
}

; Direct DLL interop without manual Buffer/NumGet/NumPut
DllCall("GetCursorPos", "Ptr", pt := POINT())
MsgBox pt.x ", " pt.y
```

### 2.3 Enum Types
```autohotkey
enum Color {
    Red := 0xFF0000
    Green := 0x00FF00
    Blue := 0x0000FF
}

enum Direction {
    North, South, East, West  ; auto-numbered 0-3
}
```

### 2.4 Union / Tagged Types
```autohotkey
type Result<T> := Ok(T) | Error(String)

; Pattern matching
match Divide(10, 0) {
    Ok(value) => MsgBox "Result: " value
    Error(msg) => MsgBox "Failed: " msg
}
```

---

## 3. Concurrency & Async

### 3.1 Async/Await
Replace the pseudo-thread model with real async primitives:

```autohotkey
; Async function
async FetchData(url: String) -> String {
    response := await Http.Get(url)
    return response.Body
}

; Parallel execution
async LoadDashboard() {
    ; Fire all requests concurrently
    [users, metrics, config] := await Promise.All([
        FetchData("https://api.example.com/users"),
        FetchData("https://api.example.com/metrics"),
        FetchData("https://api.example.com/config")
    ])
}

; Timeout support
try {
    result := await Promise.Race([
        FetchData(url),
        Promise.Timeout(5000)  ; 5 second timeout
    ])
}
```

### 3.2 True Multithreading
Currently only the AHK_H fork supports threads. v3 should have native support:

```autohotkey
; Worker threads with message passing (no shared mutable state)
worker := Thread(() => {
    ; Runs in separate OS thread
    result := ExpensiveComputation(data)
    Thread.PostMessage(result)
})

; Receive results
worker.OnMessage((result) => {
    UpdateGui(result)
})

; Thread pool for CPU-bound work
pool := ThreadPool(4)  ; 4 workers
results := await pool.Map(items, ProcessItem)
```

### 3.3 Channels
Go-style channels for thread communication:

```autohotkey
ch := Channel<String>(bufferSize: 10)

; Producer thread
Thread(() => {
    loop {
        ch.Send(ReadSensorData())
    }
})

; Consumer (main thread)
for data in ch {
    UpdateDisplay(data)
}
```

---

## 4. Error Handling & Debugging

### 4.1 Richer Error Objects
Drawing from this project's experience building the MCP error agent:

```autohotkey
; Errors carry full context natively
try {
    ProcessFile("data.csv")
} catch FileError as e {
    ; Available natively, no _ScriptGetLines() hack needed
    e.Message       ; "File not found: data.csv"
    e.File          ; "C:\Scripts\main.ahk"
    e.Line          ; 42
    e.Column        ; 5
    e.Stack         ; Full stack trace as structured array
    e.SourceContext ; Lines around the error (built-in)
    e.Cause         ; Chained inner exception
    e.Data          ; Arbitrary metadata Map
}
```

### 4.2 Error Cause Chaining
```autohotkey
try {
    db.Query("SELECT * FROM users")
} catch DbError as e {
    throw AppError("Failed to load users", cause: e)
}
; Stack trace shows full chain: AppError -> DbError -> SocketError
```

### 4.3 Result Type (Error-as-Value)
For cases where exceptions are too heavy:

```autohotkey
; Functions can return Result instead of throwing
ReadConfig(path: String) -> Result<Config, FileError> {
    if !FileExist(path)
        return Err(FileError("Config not found: " path))
    return Ok(ParseConfig(FileRead(path)))
}

; Caller handles explicitly
match ReadConfig("settings.ini") {
    Ok(config) => ApplyConfig(config)
    Err(e) => UseDefaults()
}

; Or propagate with ? operator
LoadApp() -> Result<App, Error> {
    config := ReadConfig("settings.ini")?  ; returns Err early if failed
    db := ConnectDb(config.dbUrl)?
    return Ok(App(config, db))
}
```

### 4.4 Native Debug Protocol Improvements
Based on DBGp limitations found in this project's debugger work:

- **Multiple simultaneous debugger connections** — allow IDE + MCP server at the same time
- **Configurable debug port** — not hardcoded to 9000
- **WebSocket transport** — for browser-based and remote debugging
- **Conditional breakpoints with expressions** — `break when i > 1000`
- **Logpoints** — breakpoints that log without stopping: `log "x={x}, y={y}"`
- **Data breakpoints** — break when a variable's value changes
- **Built-in profiling** — execution time per function, hotspot identification
- **Memory profiling** — track allocations, detect leaks
- **Hot reload** — modify running scripts without restarting

### 4.5 Structured Logging
```autohotkey
; Built-in structured logging (not just FileAppend to stderr)
Log.Info("User logged in", { user: name, ip: addr })
Log.Error("Query failed", { sql: query, error: e })

; Configurable outputs
Log.AddOutput(FileOutput("app.log", format: "json"))
Log.AddOutput(StdErrOutput(format: "text", color: true))
Log.AddOutput(EventLogOutput())  ; Windows Event Log
```

---

## 5. Cross-Platform Foundation

### 5.1 Platform Abstraction Layer
The biggest community request. v3 should at minimum lay the groundwork:

```
┌─────────────────────────────────┐
│        AHK v3 Script API        │  ← Platform-agnostic
├─────────────────────────────────┤
│     Platform Abstraction Layer  │
├──────────┬──────────┬───────────┤
│ Windows  │  Linux   │  macOS    │  ← Platform backends
│ WinAPI   │  X11/    │  Cocoa/   │
│ COM/UIA  │  Wayland │  CGEvent  │
└──────────┴──────────┴───────────┘
```

- **Core language** works identically everywhere (variables, control flow, classes, modules)
- **Platform-specific features** behind conditional imports: `Import "win/com" if A_Platform == "Windows"`
- **Hotkey abstraction** — unified API, platform-specific backends (WinAPI / X11 / CGEvent)
- **GUI abstraction** — native look on each platform via backend adapters
- **File paths** — unified path handling (`/` works everywhere, `A_PathSep` for when it matters)

### 5.2 Conditional Compilation
```autohotkey
#If A_Platform == "Windows"
    LaunchApp(path) => Run(path)
#ElseIf A_Platform == "Linux"
    LaunchApp(path) => RunWait("xdg-open " path)
#ElseIf A_Platform == "macOS"
    LaunchApp(path) => RunWait("open " path)
#EndIf
```

---

## 6. Performance & Compilation

### 6.1 Bytecode Compilation
Move beyond the current interpreted model:

- **Bytecode compiler** — compile scripts to an intermediate representation at load time
- **Ahead-of-time optimization** — constant folding, dead code elimination, inlining
- **Cached bytecode** — `.ahkc` files skip re-parsing on subsequent runs
- **Optional JIT** — hot loops compiled to native code (long-term goal)

### 6.2 Memory Management Improvements
- **Generational garbage collector** — replace reference counting for cycles
- **Weak references** — `WeakRef(obj)` for caches and observers without preventing collection
- **Value types** — structs and small objects allocated on stack, not heap
- **String interning** — deduplicate identical string literals

### 6.3 Native Data Structures
```autohotkey
; Typed arrays for performance-critical code
pixels := Int32Array(width * height)  ; contiguous memory, no boxing

; Sets
visited := Set<String>()
visited.Add("node-1")
if visited.Has("node-1") { ... }

; Ordered maps
config := OrderedMap()

; Deque (double-ended queue)
queue := Deque<Task>()
queue.PushBack(task)
item := queue.PopFront()
```

---

## 7. GUI Modernization

### 7.1 Declarative GUI
```autohotkey
; Declarative layout (inspired by modern UI frameworks)
app := Gui("My App", {
    width: 400,
    height: 300,
    layout: Column([
        Text("Enter your name:"),
        nameField := Edit({ placeholder: "Name..." }),
        Row([
            Button("OK", (*) => Submit()),
            Button("Cancel", (*) => app.Close())
        ], { spacing: 10 })
    ], { padding: 20, spacing: 10 })
})
```

### 7.2 Data Binding
```autohotkey
; Reactive data binding
state := Reactive({
    name: "",
    count: 0
})

nameLabel := Text({ text: () => "Hello, " state.name "!" })
; nameLabel updates automatically when state.name changes

state.name := "World"  ; GUI updates immediately
```

### 7.3 Web View Control
```autohotkey
; Embedded web content (via WebView2 on Windows, WebKitGTK on Linux)
webView := WebView({
    url: "https://example.com",
    ; or inline HTML
    html: "<h1>Dashboard</h1><div id='chart'></div>"
})

; JavaScript bridge
webView.Eval("document.getElementById('chart').innerHTML = '" chartHtml "'")
webView.OnMessage("js-event", (data) => HandleEvent(data))
```

---

## 8. Interop & FFI

### 8.1 Improved DllCall with Structs
```autohotkey
; Current v2: painful manual buffer management
; buf := Buffer(8), NumPut("Int", x, buf, 0), NumPut("Int", y, buf, 4)

; v3: direct struct passing
struct POINT { x: Int32, y: Int32 }
DllCall("GetCursorPos", POINT, pt := POINT())

; Callback definitions with types
callback := DllCallback((hwnd: Ptr, msg: UInt, wp: Ptr, lp: Ptr) -> Int {
    ; ...
    return 0
}, "Int", ["Ptr", "UInt", "Ptr", "Ptr"])
```

### 8.2 COM Improvements
```autohotkey
; Type-aware COM with IntelliSense support
excel := ComObject<Excel.Application>("Excel.Application")
excel.Visible := true  ; IDE knows this property exists
wb := excel.Workbooks.Add()  ; IDE shows available methods

; Async COM events
excel.OnEvent("WorkbookOpen", async (wb) => {
    await ProcessWorkbook(wb)
})
```

### 8.3 Native JSON
```autohotkey
; Built-in, not a library
data := JSON.Parse(FileRead("config.json"))
data.settings.theme := "dark"
FileWrite(JSON.Stringify(data, indent: 2), "config.json")

; JSON path queries
value := JSON.Query(data, "$.settings.theme")
```

### 8.4 Native HTTP Client
```autohotkey
; Built-in HTTP (currently requires COM/WinHTTP or libraries)
response := await Http.Get("https://api.example.com/data", {
    headers: { "Authorization": "Bearer " token },
    timeout: 5000
})

if response.Status == 200 {
    data := JSON.Parse(response.Body)
}

; WebSocket
ws := await WebSocket.Connect("wss://stream.example.com")
ws.OnMessage((msg) => ProcessMessage(msg))
await ws.Send(JSON.Stringify({ type: "subscribe", channel: "updates" }))
```

---

## 9. Developer Experience

### 9.1 Official LSP (Language Server Protocol)
- **Ship with AHK v3** — not a community add-on
- **Full IntelliSense** — leveraging type annotations and module metadata
- **Inline diagnostics** — catch errors before running
- **Refactoring support** — rename symbol, extract function, move to module
- **Code actions** — auto-import, generate struct from DllCall usage
- **Debugger integration** — DAP (Debug Adapter Protocol) alongside LSP

### 9.2 Built-in Testing Framework
```autohotkey
Import { Test, Assert } from "std/test"

Test.Describe("String utilities", {
    Test.It("should trim whitespace", () => {
        Assert.Equal(Trim("  hello  "), "hello")
    })

    Test.It("should split on delimiter", () => {
        parts := StrSplit("a,b,c", ",")
        Assert.Equal(parts.Length, 3)
        Assert.Equal(parts[1], "a")
    })
})
```

Run with `ahk test` CLI command.

### 9.3 Documentation Generator
```autohotkey
/**
 * Reads a configuration file and returns a Config object.
 * @param path - Path to the config file (INI or JSON)
 * @returns Parsed configuration
 * @throws FileError if the file doesn't exist
 * @example
 *   config := ReadConfig("settings.ini")
 *   MsgBox config.Get("General", "Theme")
 */
ReadConfig(path: String) -> Config {
    ; ...
}
```

Generate docs with `ahk doc --output html`.

### 9.4 REPL
```
$ ahk repl
AutoHotkey v3.0.0 REPL
>>> x := 42
42
>>> x * 2
84
>>> MsgBox "Hello"   ; opens a message box
>>> .help             ; show REPL commands
```

### 9.5 Script Bundler / True Compiler
- **Single-file bundler** — resolve all imports into one script
- **True compilation** — compile to native `.exe` with actual performance gains (not just bundled interpreter)
- **Tree shaking** — only include code paths that are actually used
- **Resource embedding** — bundle icons, images, data files into the exe

---

## 10. AI & Automation Integration

### 10.1 Structured Error Output
Drawing directly from this project's MCP error agent work:

```autohotkey
; Native structured error reporting (no external handler needed)
#ErrorFormat "json"  ; or "text", "xml"

; Errors automatically include:
; - Full stack trace with source context
; - Variable values in scope at crash point
; - OS/AHK version metadata
; - Deterministic error codes for programmatic handling
```

### 10.2 Script Introspection API
```autohotkey
; Programmatic access to script structure (for tooling and AI)
Import { Reflect } from "std/reflect"

; Get all functions in current module
funcs := Reflect.Functions()
for f in funcs {
    f.Name        ; "ProcessFile"
    f.Parameters  ; [{name: "path", type: "String"}, ...]
    f.ReturnType  ; "Result<Data, Error>"
    f.SourceFile  ; "main.ahk"
    f.SourceLine  ; 42
}

; Get source code programmatically
source := Reflect.Source(ProcessFile)  ; returns function source text
```

### 10.3 Headless / CI Mode (First-Class)
Building on this fork's console mode work:

```bash
# Run headless with structured output
ahk run --headless --output json script.ahk

# Run tests in CI
ahk test --reporter junit --output results.xml

# Lint and type-check without executing
ahk check script.ahk --strict

# Format code
ahk fmt script.ahk
```

### 10.4 Plugin / Extension API
```autohotkey
; Scripts can expose tools/capabilities to external systems
#Plugin {
    name: "file-processor",
    version: "1.0.0",
    capabilities: ["process-csv", "process-json"]
}

Export async ProcessCSV(input: String) -> String {
    ; Can be called by external tools, MCP servers, etc.
}
```

---

## 11. Syntax & Language Improvements

### 11.1 Pattern Matching
```autohotkey
match value {
    0 => "zero"
    1..10 => "small"
    n if n > 100 => "large: " n
    _ => "other"
}

; Destructuring match
match response {
    { status: 200, body } => ProcessBody(body)
    { status: 404 } => HandleNotFound()
    { status: s } if s >= 500 => HandleServerError(s)
}
```

### 11.2 Destructuring Assignment
```autohotkey
; Array destructuring
[first, second, ...rest] := GetItems()

; Object destructuring
{ name, age, email } := GetUser()

; Nested
{ address: { city, state } } := GetUser()

; In function parameters
PrintUser({ name, age }) {
    MsgBox name " is " age " years old"
}
```

### 11.3 String Interpolation Improvements
```autohotkey
; Multi-line template strings
html := `
    <div class="user">
        <h1>{user.name}</h1>
        <p>Age: {user.age}</p>
        <p>Joined: {FormatTime(user.joinDate, "yyyy-MM-dd")}</p>
    </div>
`

; Tagged templates for safe SQL, HTML, etc.
query := sql`SELECT * FROM users WHERE name = {name}`
; Automatically parameterized — no SQL injection
```

### 11.4 Pipeline Operator
```autohotkey
; Chain transformations readably
result := data
    |> Filter(_, x => x.active)
    |> Map(_, x => x.name)
    |> Sort(_)
    |> Join(_, ", ")
```

### 11.5 Null Safety
```autohotkey
; Optional chaining
city := user?.address?.city  ; returns "" if any part is unset

; Null coalescing
name := user.name ?? "Anonymous"

; Null coalescing assignment
config.timeout ??= 5000
```

---

## 12. Migration & Compatibility

### 12.1 v2-to-v3 Migration Tool
Learning from the painful v1-to-v2 transition:

- **Automated converter** that actually works — cover 95%+ of v2 syntax
- **Per-file migration** — convert incrementally, not all-or-nothing
- **Compatibility mode** — `#Requires v2-compat` for gradual transition
- **Migration diagnostics** — `ahk migrate --check script.ahk` shows what would change
- **Escape hatch** — `#Legacy { ... }` blocks for code that can't be converted yet

### 12.2 Semantic Versioning Commitment
- v3.0 is the only release that breaks v2 compatibility
- v3.x releases are backward-compatible within v3
- Deprecation warnings for at least 2 minor versions before removal
- Clear upgrade guides for each minor release

---

## Priority Tiers

### Tier 1 — Foundation (Must-Have for v3.0)
| Feature | Rationale |
|---------|-----------|
| Module system (mature) | Code organization is fundamental |
| Type annotations (optional) | Enables all tooling improvements |
| Structs as first-class types | DLL interop is a core use case |
| Richer error objects | Current error context is insufficient |
| Enums | Basic language completeness |
| Null safety operators | Eliminates a class of runtime errors |
| Official LSP | Developer experience baseline |
| v2 migration tool | Community trust and adoption |

### Tier 2 — High Impact (v3.0 or v3.1)
| Feature | Rationale |
|---------|-----------|
| Async/await | Non-blocking I/O is expected in modern languages |
| Native JSON | Most common data format, shouldn't need a library |
| Native HTTP client | Web interaction is ubiquitous |
| Package manager | Ecosystem growth depends on this |
| Pattern matching | Major expressiveness gain |
| Destructuring | Reduces boilerplate significantly |
| Built-in test framework | Quality ecosystem needs testing |
| Headless/CI mode | Automation use cases growing fast |
| Structured logging | Observability for production scripts |

### Tier 3 — Strategic (v3.x Releases)
| Feature | Rationale |
|---------|-----------|
| True multithreading | CPU-bound workloads |
| Cross-platform layer | Largest community request, but hardest |
| Bytecode compilation | Performance gains |
| Declarative GUI | Modern UI patterns |
| WebView control | HTML/JS-based UIs |
| REPL | Learning and exploration |
| True native compilation | Long-term performance goal |
| Plugin/extension API | Ecosystem extensibility |

---

## How This List Helps AI-Assisted Development

This features list serves as a reference for LLM-assisted AHK development:

1. **Code generation** — AI can generate v3-style code with proper types, modules, and error handling patterns even before v3 ships, establishing conventions early
2. **Migration assistance** — AI can convert v2 scripts toward v3 patterns incrementally
3. **Architecture guidance** — when helping users structure AHK projects, AI can recommend module boundaries and type annotations that will map cleanly to v3
4. **Error analysis** — the structured error format described here is what this project's MCP error agent already approximates; v3 makes it native
5. **Training data** — this document itself helps LLMs understand what v3 code should look like, addressing the community's concern about AI generating outdated v1 syntax
