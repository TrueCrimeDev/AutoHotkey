# Build & install

The Console fork runs on Windows. ClautoHotkey's shell hooks additionally need WSL or Git Bash and `jq`; the grading checker uses Python 3.

::: info Public download status
On September 17, 2026, this repository had no published GitHub releases. Do not depend on a `releases/latest` executable download. Build the source, or use a build artifact whose provenance and capabilities you have verified.
:::

## Clone the source

```powershell
git clone --branch alpha https://github.com/TrueCrimeDev/AutoHotkey.git C:\Source\AutoHotkey
Set-Location C:\Source\AutoHotkey
```

## Build a Console target

The repository supports MinGW-w64 and MSVC. For this explicit Console-target route, open a Visual Studio developer command prompt with C++ tools, CMake, and Ninja available:

```bat
cmake -S . -B build_console -G Ninja -DCMAKE_BUILD_TYPE=Release -DAHK_OUTPUT_DIR=bin_console
cmake --build build_console --target AutoHotkey64Console --parallel 6
bin_console\AutoHotkey64Console.exe --version
bin_console\AutoHotkey64Console.exe --capabilities
```

The ordinary GUI target is a different launch mode. Building the default target alone may not produce `AutoHotkey64Console.exe`. Use a separate x86 build environment for `AutoHotkey32Console`.

For the GCC toolchain setup, helper scripts, and alternative Visual Studio builds, read the repository's [BUILD.md](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/BUILD.md).

## Verify the exact executable

```powershell
python tests/run_console_gate.py bin_console/AutoHotkey64Console.exe
```

Use that same executable path in your shell alias, `harness.env`, and MCP configuration. Mismatched interpreters are a common source of “works here, fails there.”

The optional `tree-sitter-ahk.dll` belongs beside the x64 engine for grammar-backed tools. The bundled grammar DLL is x64-only; do not load it into a Win32 process.

## Add a temporary PowerShell alias

```powershell
Set-Alias ahk 'C:\Source\AutoHotkey\bin_console\AutoHotkey64Console.exe'
ahk --version
```

This affects the current shell. The repository's `tools/ahk.ps1` is another option once the executable is in the path that wrapper expects. Check the resulting alias with `Get-Command ahk`.

::: warning Development features
The screenshots and development feature reference include working-tree additions tested against an alpha.31 build. A clean clone of `alpha` is not a promise that every preview feature is available. Inspect [capabilities and availability](/guide/compatibility) before running an advanced example.
:::
