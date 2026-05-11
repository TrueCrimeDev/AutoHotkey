# AutoHotkey Debugger — Claude Code Hooks

## Overview

These hooks teach Claude Code how to use the AutoHotkey MCP debugging ecosystem. They fire at key lifecycle points to inject context, guide workflows, and ensure Claude follows the correct debugging patterns.

## Architecture

```
Claude Code (AI)
    ↕  MCP protocol (JSON-RPC over stdio)
MCP Server (Node.js, spawned by Claude Code)
    ↕  DBGp protocol (XML over TCP port 9000)
AutoHotkey.exe /Debug (user launches manually)
```

The MCP server (`autohotkey-debug`) is defined in `.mcp.json` at the project root. Claude Code spawns it as a child process. It listens on port 9000 for AutoHotkey to connect.

## The 3 Hooks

### 1. `ahk-debug-context.sh` — Session Context Injection

**Event:** `SessionStart` (fires on startup, resume, and after context compaction)

**Purpose:** Ensures Claude Code always has the full debugger reference in context, even after the conversation is compacted. Outputs:
- All 22 MCP tool names and descriptions
- Workflow rules (connection order, blocking calls, error loop)
- `analyze_error` dual modes (client-side vs API)
- Watch system behavior (auto-snapshot on step)
- Custom AHK engine features (/Headless, /Diag, check, test)
- AHK v2 syntax reminders

**Why it matters:** Without this, Claude loses debugger knowledge after compaction and starts hallucinating tool names or forgetting workflow order.

### 2. `check-ahk-connection.sh` — Pre-Tool Connection Hint

**Event:** `PreToolUse` (matcher: `mcp__autohotkey-debug__.*`)

**Purpose:** Fires before any debugger MCP tool call. Injects `additionalContext` telling Claude to guide the user to launch AHK with `/Debug` if the tool returns a connection error.

**Why it matters:** The most common failure mode is calling `debug_run` or `capture_error` when no AHK process is connected. This hook ensures Claude gives the right instruction instead of retrying blindly.

**Note:** This hook does NOT block — it only adds context. The tool call proceeds normally.

### 3. `post-capture-guidance.sh` — Workflow Guidance

**Event:** `PostToolUse` (matcher: `capture_error|analyze_error|apply_fix`)

**Purpose:** Reads the tool output and injects next-step guidance:

| Tool | Output | Guidance |
|------|--------|----------|
| `capture_error` | timeout | Suggest retry or check `debug_status` |
| `capture_error` | error captured | Nudge: analyze → fix → re-run |
| `analyze_error` | `status: "analyzed"` | Apply fix if confidence >= 0.7 |
| `analyze_error` | `status: "api_error"` | Analyze the prompt yourself |
| `analyze_error` | prompt returned | Do client-side analysis |
| `apply_fix` | `success: true` | Tell user to re-run |
| `apply_fix` | `success: false` | Read actual line, adjust, retry |

**Why it matters:** Without this, Claude often skips steps (e.g., applies a fix without showing the diagnosis) or gets stuck after a failure.

## Settings Configuration

Add this to your `.claude/settings.local.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/ahk-debug-context.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "mcp__autohotkey-debug__.*",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/check-ahk-connection.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__autohotkey-debug__capture_error|mcp__autohotkey-debug__analyze_error|mcp__autohotkey-debug__apply_fix",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-capture-guidance.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Merge this with your existing settings (permissions, etc.).

## MCP Server Configuration

Your `.mcp.json` (project root) should contain:

```json
{
  "mcpServers": {
    "autohotkey-debug": {
      "command": "node",
      "args": [
        "C:\\Users\\uphol\\Documents\\Design\\Coding\\AutoHotkey\\debugger-tool\\mcp-server\\build\\index.js"
      ],
      "env": {}
    }
  }
}
```

To enable Claude API integration in `analyze_error(use_api=true)`, add your key:

```json
"env": { "ANTHROPIC_API_KEY": "sk-ant-..." }
```

## MCP Tool Reference

### Execution Control
| Tool | Description |
|------|-------------|
| `debug_run` | Continue until breakpoint or error |
| `debug_step_into` | Step into functions (returns watch changes) |
| `debug_step_over` | Step over functions (returns watch changes) |
| `debug_step_out` | Step out of current function (returns watch changes) |
| `debug_stop` | End debug session |
| `debug_status` | Get current status |
| `debug_command` | Raw DBGp command passthrough |

### Breakpoints
| Tool | Params | Description |
|------|--------|-------------|
| `breakpoint_set` | `file, line, condition?` | Set breakpoint, returns ID |
| `breakpoint_remove` | `id` | Remove by ID |
| `breakpoint_list` | — | List all active |

### Inspection
| Tool | Params | Description |
|------|--------|-------------|
| `variables_get` | `context? (0=local, 1=global)` | All vars in scope |
| `evaluate` | `expression` | Eval in current context |
| `stack_trace` | — | Call stack frames |

### Source Intelligence
| Tool | Params | Description |
|------|--------|-------------|
| `get_source_context` | `file, line, radius?` | Lines around a location |
| `source_outline` | `file` | Functions, classes, hotkeys, labels |
| `workspace_symbols` | `root?, query?, max_results?` | Scan all .ahk files |

### Error Loop
| Tool | Params | Description |
|------|--------|-------------|
| `capture_error` | `timeout?` | **BLOCKING** wait for exception (default 30s) |
| `analyze_error` | `error, use_api?` | Diagnose error (client or API) |
| `apply_fix` | `file, line, original, replacement` | Verified line replacement |
| `list_errors` | — | Show queued errors |
| `clear_errors` | — | Empty error queue |

### Variable Watches
| Tool | Params | Description |
|------|--------|-------------|
| `watch_add` | `name` | Track variable/expression |
| `watch_remove` | `name` | Stop tracking |
| `watch_list` | — | Snapshot all with current values |

Step commands (`step_into`, `step_over`, `step_out`) automatically include watch snapshots:
```json
{
  "status": "break",
  "line": 15,
  "watches": [
    { "name": "counter", "value": "5", "previous": "4", "changed": true },
    { "name": "name", "value": "\"Alice\"", "previous": "\"Alice\"", "changed": false }
  ]
}
```

## Workflow Patterns

### Pattern 1: Error Fix Loop
```
capture_error → analyze_error → apply_fix → user re-runs
```
1. Call `debug_run` first (starts execution)
2. Call `capture_error` (blocks waiting for exception)
3. Call `analyze_error(error, use_api=true)` for API diagnosis
4. If confidence >= 0.7, call `apply_fix` with the suggested fix
5. Tell user to re-run: `bin\AutoHotkey64.exe /Debug script.ahk`

### Pattern 2: Interactive Stepping
```
breakpoint_set → debug_run → watch_add → debug_step_over (repeat)
```
1. Set breakpoints at interesting locations
2. `debug_run` to hit first breakpoint
3. `watch_add` for variables you want to track
4. `debug_step_over` repeatedly — watch changes appear in response
5. Use `variables_get` or `evaluate` for deeper inspection

### Pattern 3: Quick Syntax Check
```bash
bin\AutoHotkey64.exe check script.ahk        # exit 0=ok, 13=fail
bin\AutoHotkey64.exe /Diag=json check script.ahk  # JSON output
```
No debugger needed — runs and exits immediately.

## Troubleshooting

**"Not connected to AutoHotkey debugger"**
→ User hasn't launched AHK with `/Debug`. Tell them: `bin\AutoHotkey64.exe /Debug script.ahk`

**`capture_error` times out**
→ Script ran without errors, or wasn't started. Check `debug_status`.

**`apply_fix` line mismatch**
→ File was modified since the error was captured. Read `get_source_context` for current content and adjust.

**`analyze_error` returns `api_error`**
→ `ANTHROPIC_API_KEY` not set in `.mcp.json` env block. Fall back to client-side analysis.

**Watch shows `<error>`**
→ Variable not in scope at current execution point. It may exist in a different stack frame.

**Watch shows `<undefined>`**
→ Expression evaluated to empty. Variable may not be initialized yet.
