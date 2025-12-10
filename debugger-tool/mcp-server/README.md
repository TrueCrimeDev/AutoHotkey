# MCP Server for AutoHotkey v2 Debugging

**Connect AI tools (Cursor, Claude Desktop, Windsurf) to AutoHotkey debugger**

This MCP server bridges AI assistants to AutoHotkey's DBGp debugger, enabling AI-powered debugging workflows.

## Architecture

```
AI Tool (Cursor/Claude) <--stdio MCP--> MCP Server <--DBGp--> AutoHotkey
```

Similar to [mcp-debug-tools](https://github.com/hwanyong/mcp-debug-tools) but for AutoHotkey instead of VSCode.

## Quick Start

### 1. Install Dependencies

```bash
cd debugger-tool/mcp-server
npm install
npm run build
```

### 2. Configure Your AI Tool

**Cursor:**

Edit `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "autohotkey-debug": {
      "command": "node",
      "args": [
        "/absolute/path/to/AutoHotkey/debugger-tool/mcp-server/build/index.js"
      ]
    }
  }
}
```

**Claude Desktop:**

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` (Mac) or
`%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "autohotkey-debug": {
      "command": "node",
      "args": [
        "C:\\path\\to\\AutoHotkey\\debugger-tool\\mcp-server\\build\\index.js"
      ]
    }
  }
}
```

### 3. Start Debugging

**Terminal 1 - Start AI Tool:**
```bash
# Cursor or Claude Desktop will auto-start the MCP server
# Just open the app
```

**Terminal 2 - Start AutoHotkey:**
```bash
AutoHotkey.exe /Debug your_script.ahk
```

### 4. Use in AI Chat

```
You: "Set a breakpoint at line 10 in my script and step through the code"

AI: I'll help you debug. Let me set that breakpoint...
    [Uses breakpoint_set tool]
    Breakpoint set at line 10. Now stepping through...
    [Uses debug_step_into tool]
    Current line: 10, variable x = 5
```

## Available MCP Tools

### Debug Control

| Tool | Description |
|------|-------------|
| `debug_run` | Continue execution until next breakpoint |
| `debug_step_into` | Step into function (line by line) |
| `debug_step_over` | Step over function |
| `debug_step_out` | Step out of current function |
| `debug_stop` | Stop debug session |
| `debug_status` | Get current status |

### Breakpoints

| Tool | Description |
|------|-------------|
| `breakpoint_set` | Set breakpoint at file:line with optional condition |
| `breakpoint_remove` | Remove breakpoint by ID |
| `breakpoint_list` | List all breakpoints |

### Variables

| Tool | Description |
|------|-------------|
| `variables_get` | Get all variables in scope |
| `evaluate` | Evaluate expression in current context |

### Stack

| Tool | Description |
|------|-------------|
| `stack_trace` | Get current call stack |

## Available MCP Resources

| Resource | URI | Description |
|----------|-----|-------------|
| Breakpoints | `ahk://breakpoints` | List of active breakpoints |
| Variables | `ahk://variables` | Current scope variables |
| Stack | `ahk://stack` | Call stack trace |
| Status | `ahk://status` | Debug session status |

## Example AI Workflows

### 1. Finding a Bug

**You:** "My calculateTotal function returns the wrong value. Can you debug it?"

**AI workflow:**
```typescript
// 1. Set breakpoint at function start
await breakpoint_set({ file: "script.ahk", line: 15 })

// 2. Run to breakpoint
await debug_run()

// 3. Step through and inspect variables
await debug_step_into()
const vars = await variables_get({ context: 0 })

// 4. Evaluate expressions
const result = await evaluate({ expression: "total" })

// 5. Continue stepping to find the issue
await debug_step_over()
```

**AI:** "I found the issue! Line 18 uses `+` instead of `*` for multiplication..."

### 2. Understanding Code Flow

**You:** "Show me the execution path when the user clicks the button"

**AI workflow:**
```typescript
// 1. Set breakpoint at event handler
await breakpoint_set({ file: "script.ahk", line: 45 })

// 2. Run and hit breakpoint
await debug_run()

// 3. Get call stack to see execution path
const stack = await stack_trace()

// 4. Step through each function
for (let i = 0; i < 10; i++) {
  await debug_step_into()
  const vars = await variables_get({ context: 0 })
  // Record state at each step
}
```

**AI:** "Here's the execution flow: Button click → OnClick() → ValidateInput() → ProcessData()..."

### 3. Conditional Debugging

**You:** "Break when counter > 100"

**AI workflow:**
```typescript
// Set conditional breakpoint
await breakpoint_set({
  file: "script.ahk",
  line: 30,
  condition: "counter > 100"
})

await debug_run()
// Breaks only when condition is true
```

**AI:** "Breakpoint hit at line 30 when counter = 101"

## Development

### Build

```bash
npm run build
```

### Watch Mode

```bash
npm run watch
```

### Test Locally

```bash
# Terminal 1
node build/index.js

# Terminal 2
AutoHotkey.exe /Debug test_script.ahk

# Terminal 3 - Test MCP connection
node test-mcp-connection.js
```

## Troubleshooting

### "Not connected to AutoHotkey debugger"

- Make sure AutoHotkey is running with `/Debug` flag
- Check that port 9000 is not in use
- Verify AutoHotkey connects before AI tool sends commands

### "Command timeout"

- AutoHotkey may be in running state
- Try `debug_status` to check current state
- May need to pause execution first

### AI tool doesn't see the MCP server

- Restart the AI tool completely
- Check config file path is absolute
- Verify `node` is in PATH
- Check MCP server logs in AI tool's console

## Comparison with mcp-debug-tools

| Feature | mcp-debug-tools (VSCode) | This (AutoHotkey) |
|---------|-------------------------|-------------------|
| **Target** | VSCode DAP | AutoHotkey DBGp |
| **Protocol** | DAP (JSON-RPC) | DBGp (XML) |
| **Architecture** | VSCode Ext + CLI + MCP | Direct MCP to DBGp |
| **Setup** | VSCode extension required | Just Node.js |
| **Languages** | Any VSCode debugger | AutoHotkey only |
| **Connection** | HTTP + stdio | stdio + TCP |

## Implementation Details

### DBGp Protocol

AutoHotkey uses the DBGp protocol (same as Xdebug):

```
Client (MCP Server)    Server (AutoHotkey)
    |                        |
    | <--- TCP connect ----- | (port 9000)
    | <--- init message ---- |
    | -- run -i 1 --------> |
    | <-- response --------- |
```

### Message Format

**Commands (to AutoHotkey):**
```
step_into -i 1\0
```

**Responses (from AutoHotkey):**
```
125\0<?xml version="1.0"?>
<response command="step_into" transaction_id="1" status="break"/>
\0
```

### MCP Integration

The server translates MCP tool calls to DBGp commands:

```typescript
MCP Tool: breakpoint_set({ file: "a.ahk", line: 10 })
    ↓
DBGp: breakpoint_set -t line -f file:///a.ahk -n 10 -i 1\0
    ↓
AutoHotkey: Sets breakpoint, returns ID
    ↓
MCP Response: "Breakpoint set: ID=1, a.ahk:10"
```

## Future Enhancements

- [ ] Multi-session support (multiple AutoHotkey instances)
- [ ] Watch expressions
- [ ] Exception breakpoints
- [ ] Performance profiling
- [ ] Log points (non-breaking breakpoints)
- [ ] Hot reload (modify code during debug)

## License

MIT

## Related Projects

- [mcp-debug-tools](https://github.com/hwanyong/mcp-debug-tools) - MCP server for VSCode debugging
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification
- [AutoHotkey v2](https://www.autohotkey.com/) - AutoHotkey language
