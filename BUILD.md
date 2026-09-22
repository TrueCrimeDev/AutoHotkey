# Building AHK Console

This fork targets AutoHotkey `2.1-alpha.31+Console`. CMake supports MSVC x64,
MSVC Win32, and mingw-w64 GCC x64. CI builds and tests the actual Console
executable for all three, and tag builds publish non-draft releases with
checksums. Nothing is published by a local build.

## Executable roles

| Target | Role | Default CMake build |
| --- | --- | --- |
| `AutoHotkey64Console` / `AutoHotkey32Console` | Shell, pipelines, REPL, native MCP; attached console and terminal errors | Yes |
| `AutoHotkey64` / `AutoHotkey32` | Windows GUI launch behavior | Yes |
| `AutoHotkey64Harness` / `AutoHotkey32Harness` | Compatibility test launcher with console subsystem and GUI entrypoint behavior | No; build explicitly |

The targets share compiled engine objects. Only their entrypoints and resource
objects are compiled separately. Manifest output stays in each CMake build
directory, allowing independent architectures/toolchains to configure safely.
The Visual Studio project retains its original manifest-generation route.

## MSVC

Install Visual Studio 2022 or Build Tools 18 with the C++ Desktop Development
workload and a Windows SDK. From an x64 developer command prompt:

```cmd
cmake -S . -B build_msvc_x64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DAHK_OUTPUT_DIR=out/msvc/x64
cmake --build build_msvc_x64 --target AutoHotkey64Console AutoHotkey64 --parallel 6
python tests/run_console_gate.py out/msvc/x64/AutoHotkey64Console.exe
python tools/check_all.py out/msvc/x64/AutoHotkey64Console.exe
```

Use a separate build directory, output directory, and x86 developer prompt for
Win32; the targets are `AutoHotkey32Console` and `AutoHotkey32`. A Visual Studio
CMake generator also works: configure with `-A x64` or `-A Win32` instead of
`-G Ninja`, and pass `--config Release` when building.

The existing `build_local.bat`, `build_vs18.cmd`, and `AutoHotkeyx.sln` routes
remain available for the GUI executable. Use CMake for the distinct Console
target and for isolated builds that do not replace an installed executable.

## GCC / mingw-w64

Install [MSYS2](https://www.msys2.org), then in its MINGW64 shell:

```bash
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
cmake -S . -B build_mingw_x64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DAHK_OUTPUT_DIR=out/mingw/x64
cmake --build build_mingw_x64 --target AutoHotkey64Console AutoHotkey64 --parallel 6
```

From PowerShell, run the gate and syntax checker with
`out/mingw/x64/AutoHotkey64Console.exe`. `build.bat` remains a convenience route
using `build_gcc/` and the default `bin/` output; set `MSYS2_ROOT` if MSYS2 is not
at `C:\msys64`. CMake's default build now includes both GUI and Console targets.

GCC executables link their runtime statically. MSVC's structured exception
handling provides additional native crash diagnostics; do not assume identical
native exception behavior across compilers. No Clang route is supported here.

## Verify and use the exact build

`AHK_OUTPUT_DIR` accepts an absolute directory or a path relative to the source
tree. Debug builds use that directory with `_debug` appended. It defaults to
`bin`, but separate outputs avoid stale executable and running-file conflicts.
Always pass the intended executable path to the test gate:

```powershell
$engine = (Resolve-Path out/msvc/x64/AutoHotkey64Console.exe).Path
& $engine --version
& $engine --capabilities
python tests/run_console_gate.py $engine
python tools/check_all.py $engine
Get-FileHash -LiteralPath $engine -Algorithm SHA256
```

`--version` reports source revision, compiler, and architecture. CMake appends
`-dirty` when tracked source differs from HEAD; a dirty revision is not a complete
source manifest. A source archive without Git can supply
`-DAHK_BUILD_REVISION=<revision>`; other build routes report `unknown` unless they
define it. Treat the executable's checksum and gate results as part of a handoff.

The gate runs the QA and framework suites, CLI/REPL/MCP/DBGp checks, coverage and
trace checks, and the PowerShell wrapper against that exact engine. It applies
an outer timeout to each suite. QA children use `/Headless` and a default
30-second timeout; override with `AHK_QA_TIMEOUT_MS` (1–300000 milliseconds).
The gate's output is the current suite inventory, rather than a fixed count in
this document.

The bundled `bin/tree-sitter-ahk.dll` is x64 only. Copy it beside an isolated x64
engine for grammar/AST operations. Win32 cannot load this grammar DLL; its engine
and native MCP protocol are still tested. Check syntax with the real engine's
`check` command, because tree-sitter's grammar does not cover every language
construct.

Register a tested engine in the current PowerShell session without editing the
profile or replacing the installed binary:

```powershell
. ./tools/ahk.ps1 -EnginePath $engine
ahk --version
python tests/test_powershell_cli.py --wrapper tools/ahk.ps1 --engine $engine
```

The wrapper also accepts `AHK_CONSOLE_EXE`. Without an explicit path or that
environment variable it uses `bin/AutoHotkey64Console.exe`. Test that default
separately before making it permanent in a profile. The shell tests cover both
PowerShell 7 and Windows PowerShell 5.1 when available, with explicit UTF-8 for
Unicode pipelines. Their native argument-quoting rules still differ.

## CI artifacts and releases

Each compiler job builds GUI and Console, syntax-checks scripts with its fresh
Console, runs the aggregate gate, and uploads those binaries and SHA-256 files.
The x64 jobs also compare native and script MCP conformance with the grammar
DLL present. `tools/describe_console.py ENGINE OUTPUT` records each published
Console's actual filename, checksum, version, CLI capabilities, and MCP tool
schemas in a `.capabilities.json` artifact; use this instead of a stale tool list.
The coverage job downloads the MSVC x64 Console artifact, checks its hash, and
downloads the corresponding grammar artifact before executing tests. A `v*`
tag publishes a non-draft release only after compiler gates and coverage tests
succeed, along with Node 22 builds/tests for the shared DBGp protocol and both
TypeScript clients. Release assets include MSVC x64/Win32 GUI and Console, GCC x64 assets
with `-mingw` filenames, their checksums, and the x64 grammar DLL.

Build failures usually indicate a missing C++ workload/Windows SDK or invoking
Ninja outside the matching developer environment. Keep each compiler and
architecture in its own build directory; changing compilers in an existing
CMake cache is not supported.

## Runtime limits relevant to automation

`Eval` and REPL expressions accept at most 16,384 UTF-16 code units. Larger
expressions raise a catchable `ValueError` before parsing; REPL remains usable
for the next input. Syntax failures remain `SyntaxError`. Compiled Eval storage
still has process lifetime so returned closures remain valid.

`Check(Source)` uses the shared child runner with a 30-second timeout and an
8 MiB combined stdout/stderr capture budget. It retains `{Ok, Diagnostics, Raw}`;
spawn, timeout, and capture-limit failures produce `Ok: 0` plus a synthetic error
diagnostic. `Raw` contains stderr followed by stdout, preserving order within
each stream. Check skips the script body, but load-time directives can still
have side effects. Its temporary source and process tree are cleaned up
automatically.

Native MCP `check`, `run`, and `test` also cap combined raw output at 8 MiB.
Their `timeout_ms` defaults to 30,000 and accepts integers from 1 to 600,000.
Exceeding the capture budget terminates the child job and reports `ok: false`,
`outputLimitExceeded: true`, and `captureLimitBytes: 8388608`; captured streams
contain only the retained prefix. Timeout is reported separately as `timedOut`.

ProcessPipe timeout arguments use seconds. Invalid nonfinite or unrepresentable
timeouts raise an error instead of wrapping; zero retains the existing unlimited
wait meaning. `Read()` without a timeout remains a nonblocking read. Pipe pumping
uses bounded slices so output on one stream does not indefinitely postpone the
other stream or timeout checks.
