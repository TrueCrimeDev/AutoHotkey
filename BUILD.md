# Building AutoHotkey with _ScriptGetLines

**GCC (mingw-w64) is the canonical compiler for this fork.** MSVC remains supported as an
alternative and still produces the CI release binary.

## Prerequisites

- [MSYS2](https://www.msys2.org) with the mingw-w64 toolchain
- After installing MSYS2, in the MSYS2 shell:
  ```bash
  pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
  ```

## Quick Build (Windows)

1. From the repo root (WSL or a Windows shell), run the helper script:

   ```cmd
   build.bat
   ```

   Append `clean` to force a fresh configure; set `MSYS2_ROOT` if MSYS2 isn't at `C:\msys64`.

2. Output will be in `bin\AutoHotkey64.exe`. The build tree lives in `build_gcc/`.

CI verifies this route via the `build-mingw` job in `.github/workflows/build.yml`. The GCC
binary is statically linked (~3.2 MB). There is no Clang path — the sources only fork on
`_MSC_VER` vs mingw GCC.

## Alternative: MSVC (Visual Studio)

Smaller binary (~1.3 MB) with full SEH crash-log fidelity; this is what the CI `release` job
ships. Requires Visual Studio 2022 or Build Tools 18 with the *C++ Desktop Development* workload.

1. Use the repo helper script, which auto-detects the toolchain:

   ```cmd
   build_local.bat
   ```

   If only Visual Studio Build Tools 18 is installed, you can also run `build_vs18.cmd`.

2. Manual build — open **Developer Command Prompt for VS 2022** and run:
   ```cmd
   msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64
   ```

3. Or via the **Visual Studio GUI**: open `AutoHotkeyx.sln`, select **Release** / **x64**,
   then Build > Build Solution (Ctrl+Shift+B).

4. Output in `bin\AutoHotkey64.exe`.

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
