# Building AutoHotkey with _ScriptGetLines

## Prerequisites

- Visual Studio 2022, or Visual Studio Build Tools 18 on this machine
- C++ Desktop Development workload installed

## Quick Build (Windows)

1. Use the repo helper script, which auto-detects the supported toolchain on this machine:

   ```cmd
   build_local.bat
   ```

   If only Visual Studio Build Tools 18 is installed, you can also run:

   ```cmd
   build_vs18.cmd
   ```

2. If you prefer a manual build, open **Developer Command Prompt for VS 2022** (or the equivalent Build Tools prompt)

3. Navigate to the project:
   ```cmd
   cd C:\Users\uphol\Documents\Design\Coding\AutoHotkey
   ```

4. Build x64 Release:
   ```cmd
   msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64
   ```

5. Output will be in `bin\AutoHotkey64.exe`

## Alternative: Visual Studio GUI

1. Open `AutoHotkeyx.sln` in Visual Studio
2. Select **Release** and **x64** from the toolbar dropdowns
3. Build > Build Solution (Ctrl+Shift+B)
4. Output in `bin\AutoHotkey64.exe`

## Alternative: mingw-w64 / GCC (MSYS2)

A non-MSVC build path using GCC, handy for cross-compiling from WSL. MSVC stays the
canonical/distribution build; the mingw binary is larger (~3.2 MB) and statically linked.

1. Install [MSYS2](https://www.msys2.org), then in the MSYS2 shell:
   ```bash
   pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
   ```
2. From the repo root (WSL or a Windows shell):
   ```cmd
   cmd.exe /c build_mingw.bat
   ```
   Append `clean` to force a fresh configure; set `MSYS2_ROOT` if MSYS2 isn't at `C:\msys64`.
3. Output in `bin\AutoHotkey64.exe`. CI verifies this route via the `build-mingw` job in
   `.github/workflows/build.yml`.

There is no Clang path — the sources only fork on `_MSC_VER` vs mingw GCC.

## Build Configurations

| Config | Platform | Output |
|--------|----------|--------|
| Release | x64 | `bin\AutoHotkey64.exe` |
| Release | Win32 | `bin\AutoHotkey32.exe` |
| Debug | x64 | `bin_debug\AutoHotkey64.exe` |

## Verify _ScriptGetLines

After building, test with:

```autohotkey
#Requires AutoHotkey v2.0
MsgBox(_ScriptGetLines(A_LineFile, A_LineNumber, 2)[1].Text)
```

If it shows the MsgBox line text, the build succeeded.

## Troubleshooting

**MSBuild not found**: Use `build_local.bat` or `build_vs18.cmd`, or make sure you're using a Visual Studio developer prompt instead of regular `cmd`.

**Build errors**: Ensure you have the C++ workload installed in VS Installer.

**Missing SDK**: Install Windows 10/11 SDK via VS Installer.
