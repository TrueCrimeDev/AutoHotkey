# VS Code Debug Setup - Quick Reference

## ✅ Tasks Created

Three VS Code tasks are now available:

1. **Run AHK with Debug Interceptor**
   - Runs current file through AutoDebug.ahk
   - Errors sent to GlobalDebugServer
   - Keyboard shortcut: `Alt + F13`

2. **Run AHK Normally (No Debug)**
   - Runs current file without debugging
   - Standard AHK execution
   - Keyboard shortcut: `Ctrl + F13`

3. **Start Global Debug Server**
   - Launches GlobalDebugServer.ahk in background
   - Required for global error monitoring
   - Keyboard shortcut: `Shift + F13`

---

## Keyboard Shortcuts (Project-Specific)

| Key | Action |
|-----|--------|
| `Alt + F13` | Run with Debug Interceptor |
| `Ctrl + F13` | Run Normally (No Debug) |
| `Shift + F13` | Start Global Debug Server |

**Note:** These shortcuts only work in this workspace.

---

## How to Use

### First Time Setup:
1. Press `Shift + F13` to start GlobalDebugServer
2. Open any `.ahk` file
3. Press `Alt + F13` to run with debugging

### Daily Use:
1. Open your AHK script in VS Code
2. Press `Alt + F13`
3. Script runs with automatic error reporting
4. Check GlobalDebugServer GUI for errors

---

## Making Shortcuts Global (Optional)

To use these shortcuts in **all** VS Code workspaces:

1. Press `Ctrl + Shift + P`
2. Type: "Preferences: Open Keyboard Shortcuts (JSON)"
3. Add the following to your **user** keybindings:

```json
[
  {
    "key": "alt+f13",
    "command": "workbench.action.tasks.runTask",
    "args": "Run AHK with Debug Interceptor",
    "when": "editorLangId == ahk2 || resourceExtname == .ahk"
  },
  {
    "key": "ctrl+f13",
    "command": "workbench.action.tasks.runTask",
    "args": "Run AHK Normally (No Debug)",
    "when": "editorLangId == ahk2 || resourceExtname == .ahk"
  },
  {
    "key": "shift+f13",
    "command": "workbench.action.tasks.runTask",
    "args": "Start Global Debug Server"
  }
]
```

---

## Running Tasks Manually

If keyboard shortcuts don't work:

1. Press `Ctrl + Shift + P`
2. Type: "Tasks: Run Task"
3. Select from the list:
   - Run AHK with Debug Interceptor
   - Run AHK Normally (No Debug)
   - Start Global Debug Server

---

## Files Created

- `.vscode/tasks.json` - Task definitions
- `.vscode/keybindings.json` - Workspace-specific shortcuts
- `VSCODE_SETUP.md` - This file

---

## Troubleshooting

### Shortcut not working?
- Check that you're editing an `.ahk` file
- Reload VS Code window: `Ctrl + Shift + P` → "Reload Window"
- Verify tasks.json exists in `.vscode/` folder

### Task fails to run?
- Check that AutoHotkey is installed at: `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`
- Verify AutoDebug.ahk exists in workspace root
- Check terminal output for error messages

### GlobalDebugServer not receiving errors?
- Ensure server is running (press `Shift + F13`)
- Check Windows system tray for server icon
- Verify port 9999 is not blocked by firewall

---

## Alternative: Command Palette

You can also run tasks via Command Palette:

1. `Ctrl + Shift + P`
2. Type "task" and select "Tasks: Run Task"
3. Choose your task

---

## Quick Test

1. Create a test file: `test.ahk`
2. Add code:
   ```autohotkey
   #Requires AutoHotkey v2.0
   MsgBox("Test script")
   x := 1 / 0  ; Error
   ```
3. Press `Alt + F13`
4. Error should appear in GlobalDebugServer

---

**Happy debugging!** 🛡️
