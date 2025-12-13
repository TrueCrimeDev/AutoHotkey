# AutoHotkey v2 Forum Examples

This directory contains example scripts collected from the AutoHotkey community forums and official documentation. All scripts are written for **AutoHotkey v2**.

## Sources

Scripts were collected from:
- [AutoHotkey v2 Script Showcase](https://www.autohotkey.com/docs/v2/scripts/) - Official documentation
- [Scripts and Functions (v2) Forum](https://www.autohotkey.com/boards/viewforum.php?f=83) - Community forum
- [jNizM's ahk-scripts-v2 Collection](https://github.com/jNizM/ahk-scripts-v2) - GitHub repository

## Directory Structure

### `official-docs/`
Scripts from the official AutoHotkey v2 documentation showcase:

| Script | Description |
|--------|-------------|
| `ContextSensitiveHelp.ahk` | Shows help for selected AutoHotkey function/keyword (Ctrl+2) |
| `ControllerMouse.ahk` | Use a game controller as a mouse |
| `EasyWindowDrag.ahk` | Drag windows from any point (CapsLock/Middle-click + drag) |
| `EasyWindowDrag_KDE.ahk` | KDE-style window management (Alt+click to move/resize) |
| `EncodeHTML.ahk` | Convert strings to HTML entities |
| `FavoriteFolders.ahk` | Quick access to favorite folders via middle-click menu |
| `KeyboardOnScreen.ahk` | On-screen keyboard showing real-time key presses |
| `MinimizeToTrayMenu.ahk` | Hide windows to system tray (Win+H / Win+U) |
| `TooltipMouseMenu.ahk` | Context-sensitive popup menu via middle mouse button |
| `VolumeOSD.ahk` | Volume control with on-screen display (Win+Up/Down) |
| `WindowShading.ahk` | Roll up windows to title bar (Win+Z) |

### `jNizM-collection/`
Utility functions from jNizM's popular script collection:

| Script | Description |
|--------|-------------|
| `Base64ToString.ahk` | Decode base64 strings to readable text |
| `CreateGUID.ahk` | Generate globally unique identifiers (GUIDs) |
| `FileCountLines.ahk` | Count lines in a text file |
| `FileFindString.ahk` | Search for strings in text files |
| `IsProcessElevated.ahk` | Check if a process has admin privileges |
| `ResolveHostname.ahk` | Resolve hostnames to IP addresses |
| `StringToBase64.ahk` | Encode strings to base64 |
| `TaskBarProgress.ahk` | Show progress in Windows taskbar button |

## Usage

Each script can be run directly with AutoHotkey v2 or included in your own scripts:

```autohotkey
#Requires AutoHotkey v2.0

; Include a function
#Include "jNizM-collection\CreateGUID.ahk"

; Use the function
MsgBox CreateGUID()
```

## License

- Official documentation scripts: Part of the AutoHotkey project
- jNizM collection: MIT License (see [original repository](https://github.com/jNizM/ahk-scripts-v2))

## Additional Resources

- [AutoHotkey v2 Documentation](https://www.autohotkey.com/docs/v2/)
- [AutoHotkey Community Forums](https://www.autohotkey.com/boards/)
- [awesome-AutoHotkey](https://github.com/ahkscript/awesome-AutoHotkey) - Curated list of AHK resources
