# Building AutoHotkey with _ScriptGetLines

## Prerequisites

- Visual Studio 2022 (Community edition works)
- C++ Desktop Development workload installed

## Quick Build (Windows)

1. Open **Developer Command Prompt for VS 2022** (search in Start menu)

2. Navigate to the project:
   ```cmd
   cd C:\Users\uphol\Documents\Design\Coding\AutoHotkey
   ```

3. Build x64 Release:
   ```cmd
   msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64
   ```

4. Output will be in `bin\AutoHotkey64.exe`

## Alternative: Visual Studio GUI

1. Open `AutoHotkeyx.sln` in Visual Studio
2. Select **Release** and **x64** from the toolbar dropdowns
3. Build > Build Solution (Ctrl+Shift+B)
4. Output in `bin\AutoHotkey64.exe`

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

**MSBuild not found**: Make sure you're using Developer Command Prompt, not regular cmd.

**Build errors**: Ensure you have the C++ workload installed in VS Installer.

**Missing SDK**: Install Windows 10/11 SDK via VS Installer.
