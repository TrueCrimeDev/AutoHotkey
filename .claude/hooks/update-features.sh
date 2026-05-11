#!/bin/bash
# Auto-updates FEATURES.md with plain language documentation of _.ahk

PROJECT_DIR="/mnt/c/Users/uphol/Documents/AHK"
TARGET_FILE="$PROJECT_DIR/_.ahk"
OUTPUT_FILE="$PROJECT_DIR/FEATURES.md"

# Parse JSON from stdin to get the edited file path
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only process edits to _.ahk
if [[ "$file_path" != *"_.ahk" ]]; then
    exit 0
fi

echo "Updating FEATURES.md..."

cat > "$OUTPUT_FILE" << 'HEADER'
# _.ahk - Main Hotkey Script

> Auto-generated documentation. Last updated: DATE_PLACEHOLDER

## System Overview

This is the main AutoHotkey v2 script that runs persistently and provides:

- **Global Hotkeys** - Keyboard shortcuts available system-wide
- **Layer System** - Mouse buttons (F12-F15, RAlt) act as modifier keys that unlock additional actions
- **Hotstrings** - Text expansion triggers that auto-replace typed abbreviations
- **Window Management** - Tools for minimizing, cycling, and organizing windows
- **Clipboard Tools** - Enhanced copy/paste and clipboard history

### How Layers Work

Hold a layer key (mapped to mouse buttons via external software) to access a second set of actions:

| Layer Key | Purpose |
|-----------|---------|
| F14 | Tab navigation, clipboard operations |
| F13 | Run commands, screenshots |
| F12 | Page navigation, taskbar apps (Win+1-4) |
| RAlt | Volume control, virtual desktop switching |
| F15 | Tab management (close/reopen/new) |

---

## Global Hotkeys

HEADER

# Replace date placeholder
sed -i "s/DATE_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M')/" "$OUTPUT_FILE"

# Extract and document hotkeys with descriptions
cat >> "$OUTPUT_FILE" << 'TABLE_HEADER'
| Hotkey | Action | Description |
|--------|--------|-------------|
TABLE_HEADER

# Parse hotkeys and add descriptions
grep -E '^\s*[#^!+<>*~$]*[A-Za-z0-9_]+::' "$TARGET_FILE" | \
grep -v '#HotIf' | \
grep -v 'Hotstring' | \
grep -v '^\s*;' | \
head -25 | \
while IFS= read -r line; do
    # Extract hotkey and action
    hotkey=$(echo "$line" | sed 's/::.*//; s/^\s*//')
    action=$(echo "$line" | sed 's/.*:://; s/(.*//' | sed 's/^\s*//')

    # Generate plain language description based on action
    case "$action" in
        *Reload*) desc="Reload the script" ;;
        *ToggleDebugMode*) desc="Toggle debug overlay for layer system" ;;
        *PassPin*) desc="Type PIN code" ;;
        *LaunchUIA*) desc="Open UI Automation viewer" ;;
        *ReleaseAllKeys*) desc="Unstick all modifier keys" ;;
        *HoverScreenshot*) desc="Screenshot with hover preview" ;;
        *RestartExplorer*) desc="Restart Windows Explorer" ;;
        *OpenUnzip*) desc="Open most recent extracted folder" ;;
        *ExitAllScripts*) desc="Close all running AHK scripts" ;;
        *Minimize*) desc="Minimize active window (tracked)" ;;
        *UnMinimize*) desc="Restore last minimized window" ;;
        *SameApp) desc="Cycle to next window of same app" ;;
        *SameAppReverse*) desc="Cycle to previous window of same app" ;;
        *CloseTab*) desc="Close current tab" ;;
        *Snip.Start*) desc="Start snipping tool" ;;
        *Snip.OpenSnipper*) desc="Open snipping tool window" ;;
        *Snip.DelayedSnap*) desc="Delayed screenshot" ;;
        *Snip.GetText*) desc="OCR screenshot to text" ;;
        *PrintScreen*) desc="Take screenshot" ;;
        *EmptyBin*) desc="Empty recycle bin" ;;
        *CopyPath*) desc="Copy file path to clipboard" ;;
        *Send*) desc="Send keypress" ;;
        *) desc="$action" ;;
    esac

    # Format hotkey for readability (order matters - replace + before adding Ctrl+)
    readable=$(echo "$hotkey" | \
        sed 's/~//g; s/\$//g; s/\*//g' | \
        sed 's/+/Shift+/g' | \
        sed 's/\^/Ctrl+/g; s/!/Alt+/g; s/#/Win+/g')

    echo "| \`$readable\` | $action | $desc |" >> "$OUTPUT_FILE"
done

# Add hotstrings section
cat >> "$OUTPUT_FILE" << 'HOTSTRINGS_HEADER'

---

## Hotstrings (Text Expansion)

Type these triggers followed by a space/enter to expand:

| Trigger | Expands To |
|---------|------------|
HOTSTRINGS_HEADER

# Extract hotstrings with better parsing
grep 'XHotstring("' "$TARGET_FILE" | \
head -20 | \
while IFS= read -r line; do
    # Extract trigger - between first " and second "
    trigger=$(echo "$line" | sed 's/.*XHotstring("//; s/".*//' | sed 's/^:://')

    # Check if it's a function callback or string expansion
    if echo "$line" | grep -q '(\*) =>'; then
        # Function-based hotstring
        case "$trigger" in
            */@@*) expansion="Wrap clipboard in @{...}" ;;
            */ghu*) expansion="git pull --rebase origin main" ;;
            */gcli*) expansion="copilot --allow-all-tools" ;;
            */gc*) expansion="git clone [clipboard]" ;;
            */gu*) expansion="git pull origin main" ;;
            */clauto*) expansion="claude --dangerously-skip-permissions" ;;
            *) expansion="*(dynamic function)*" ;;
        esac
    else
        # String expansion - get second quoted string
        expansion=$(echo "$line" | sed 's/[^"]*"[^"]*", *"//; s/".*//')

        # Truncate long expansions
        if [[ ${#expansion} -gt 40 ]]; then
            expansion="${expansion:0:40}..."
        fi

        # Clean up empty
        if [[ -z "$expansion" ]]; then
            expansion="*(multiline)*"
        fi
    fi

    echo "| \`$trigger\` | $expansion |" >> "$OUTPUT_FILE"
done

# Add layer details
cat >> "$OUTPUT_FILE" << 'LAYERS'

---

## Layer Actions (Hold + Key)

### F14 Layer (Tab Navigation)
- **Wheel Up/Down** - Next/Previous tab
- **Delete** - Backspace
- **Ctrl+C** - Select all
- **Ctrl+V** - Capture text to clipboard
- **XButton1/2** - Undo/Redo

### F13 Layer (Power Actions)
- **Wheel Up/Down** - Scroll up/down
- **Delete** - Delete word
- **Ctrl+C** - Super copy (enhanced)
- **Ctrl+V** - Clipboard history
- **XButton1/2** - Unminimize/Maximize

### F12 Layer (Navigation)
- **Wheel Up/Down** - Page Up/Down
- **A/S/D/F** - Win+1/2/3/4 (taskbar apps)

### RAlt Layer (Media & Desktop)
- **Wheel Up/Down** - Volume Up/Down
- **Middle Click** - Go to playing tab
- **Delete** - Delete line
- **XButton1/2** - Previous/Next virtual desktop
- **Enter** - Maximize window

### F15 Layer (Tab Management)
- **Wheel Up/Down** - Page Up/Down
- **Left Click** - Start snip
- **Enter** - Shift+Enter
- **F13** - Debug command

---

## Window Groups & Context Hotkeys

Some hotkeys only work in specific windows:

- **Downloads folder** - Ctrl+Right extracts selected archive
- **VS Code** - Ctrl+F13 runs script (F5)
- **Discord** - Backtick hotstring for code blocks

LAYERS

echo "FEATURES.md updated successfully"
exit 0
