# AutoHotkey v2 Debugger Interception Architecture

## Overview

This document describes the complete architecture for intercepting, caching, and analyzing AutoHotkey v2 debugger (DBGp) traffic through an MCP server.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    AutoHotkey v2 Script                         │
│                   (Running with /Debug flag)                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ DBGp Protocol (TCP)
                             │ Port 9000 (default)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              Modified AutoHotkey Debugger Engine                │
│  (source/Debugger.cpp with logging interception points)        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Interception Points:                                     │  │
│  │ • Connect() - Redirect to proxy via env vars            │  │
│  │ • ReceiveCommand() - Log incoming DBGp commands         │  │
│  │ • SendResponse() - Log outgoing DBGp responses          │  │
│  │ • ProcessCommands() - Parse and cache events            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Event Cache (Circular Buffer):                           │  │
│  │ • MAX_CACHED_EVENTS = 1000                              │  │
│  │ • Stores: type, data, size, timestamp                   │  │
│  │ • Dumped to: ahk_debugger_events.log                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ TCP Socket
                             │ (Proxy redirect)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│           DBGp Proxy / MCP Server (Node.js)                     │
│        (ahk-debugger-mcp-server.js)                             │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ TCP Server (Port 9002):                                  │  │
│  │ • Listens for DBGp connections                           │  │
│  │ • Parses DBGp protocol (length-prefixed XML)             │  │
│  │ • Forwards to real debugger (optional)                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Event Cache & Indexing:                                  │  │
│  │ • In-memory event store (configurable size)              │  │
│  │ • Indexed by: transaction_id, command, breakpoint_id     │  │
│  │ • Stack snapshots on break events                        │  │
│  │ • Variable state tracking                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ MCP Tools:                                               │  │
│  │ • get_debug_events - Query cached events                 │  │
│  │ • get_breakpoints - List all breakpoints                 │  │
│  │ • get_stack_history - Stack traces over time             │  │
│  │ • get_variables - Variable states                        │  │
│  │ • search_events - Full-text search                       │  │
│  │ • export_session - Export debug session                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ MCP Resources:                                           │  │
│  │ • debug://events - All cached events                     │  │
│  │ • debug://breakpoints - Current breakpoints              │  │
│  │ • debug://stack-history - Stack snapshots                │  │
│  │ • debug://variables - Variable states                    │  │
│  │ • debug://errors - Error events only                     │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ MCP Protocol (stdio)
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Claude / LLM Client                          │
│              (Analyzing debug sessions)                         │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Command Reception Flow

```
AutoHotkey Script
    ↓
Debugger Client (IDE/VSCode)
    ↓ (DBGp command)
Modified Debugger::ReceiveCommand()
    ├→ LogDebugEvent("RECV", data, size)
    ├→ Parse command
    └→ ProcessCommands()
        ├→ Execute command
        └→ SendResponse()
            ├→ LogDebugEvent("SEND", response, size)
            └→ send() to socket
```

### 2. Event Caching Flow

```
Raw DBGp Data
    ↓
Parse XML
    ├→ Extract command name
    ├→ Extract transaction_id
    ├→ Extract status/reason
    └→ Extract context (variables, stack, etc.)
        ↓
    Create Event Object
        ├→ timestamp
        ├→ command
        ├→ transactionId
        ├→ status
        ├→ variables[]
        ├→ stack[]
        └→ breakpoints[]
            ↓
    Index Event
        ├→ byTransactionId.set(id, event)
        ├→ byCommand.set(cmd, [events])
        ├→ breakpoints.set(bpId, event)
        └→ stackSnapshots.push(snapshot)
```

### 3. Query Flow

```
MCP Tool Request
    ↓
Parse Arguments
    ↓
Query Cache
    ├→ Filter by command/transaction_id/time range
    ├→ Sort results
    └→ Limit results
        ↓
    Format Response
        ├→ JSON serialization
        ├→ Include metadata
        └→ Return to client
```

## Key Components

### 1. Modified Debugger.cpp

**File**: `source/Debugger.cpp`

**Changes**:
- Add `LogDebugEvent()` method to capture events
- Add circular buffer for event caching
- Modify `ReceiveCommand()` to log incoming data
- Modify `SendResponse()` to log outgoing data
- Modify `Connect()` to support proxy redirection

**Compilation**:
```bash
# Add to config.h or build flags
#define CONFIG_DEBUGGER_LOGGING 1

# Rebuild AutoHotkey
msbuild AutoHotkeyx.vcxproj /p:Configuration=Release
```

### 2. DBGp Proxy Server

**File**: `notes/ahk-debugger-mcp-server.js`

**Features**:
- TCP server listening on port 9002
- DBGp protocol parser
- XML event parser
- In-memory event cache with indexing
- MCP tool/resource handlers

**Dependencies**:
```json
{
  "xml2js": "^0.6.0",
  "uuid": "^9.0.0"
}
```

### 3. Event Cache Structure

```typescript
interface DebugEvent {
  id: string;                    // UUID
  timestamp: number;             // Unix timestamp
  type: 'command' | 'response' | 'stream';
  command: string;               // e.g., 'step_into', 'property_get'
  transactionId: string;         // DBGp transaction ID
  status?: string;               // 'break', 'running', 'stopped'
  reason?: string;               // 'ok', 'error', 'exception'

  // Parsed data
  variables?: Property[];
  stack?: StackFrame[];
  breakpoints?: Breakpoint[];

  // Raw data
  rawData: string;
  size: number;
}

interface EventCache {
  events: DebugEvent[];
  byTransactionId: Map<string, DebugEvent>;
  byCommand: Map<string, DebugEvent[]>;
  breakpoints: Map<string, DebugEvent>;
  stackSnapshots: StackSnapshot[];
}
```

## Interception Points

### Point 1: Connection Redirection

**Location**: `Debugger::Connect()` (line 2467)

```cpp
int Debugger::Connect(const char *aAddress, const char *aPort)
{
    // Check for proxy environment variable
    const char *proxy_host = getenv("AHK_DEBUGGER_PROXY_HOST");
    const char *proxy_port = getenv("AHK_DEBUGGER_PROXY_PORT");

    if (proxy_host && proxy_port) {
        aAddress = proxy_host;
        aPort = proxy_port;
    }

    // ... rest of function
}
```

**Usage**:
```bash
set AHK_DEBUGGER_PROXY_HOST=127.0.0.1
set AHK_DEBUGGER_PROXY_PORT=9002
AutoHotkey.exe /Debug script.ahk
```

### Point 2: Command Reception Logging

**Location**: `Debugger::ReceiveCommand()` (line 2389)

```cpp
int Debugger::ReceiveCommand(int *aCommandLength)
{
    // ... existing code ...

    if (mCommandBuf.mData[u] == '\0') {
        if (aCommandLength)
            *aCommandLength = u;

        // LOG: Capture received command
        LogDebugEvent("RECV", mCommandBuf.mData, u);

        return DEBUGGER_E_OK;
    }
}
```

### Point 3: Response Sending Logging

**Location**: `Debugger::SendResponse()` (line 2427)

```cpp
int Debugger::SendResponse(size_t aStartOffset)
{
    // LOG: Capture response before sending
    LogDebugEvent("SEND", mResponseBuf.mData + aStartOffset,
                  mResponseBuf.mDataUsed - aStartOffset);

    // ... rest of function
}
```

## DBGp Protocol Details

### Message Format

```
[length]\0[<?xml version="1.0" encoding="UTF-8"?>...]\0
```

Example:
```
123\0<?xml version="1.0" encoding="UTF-8"?><response command="step_into" status="break" reason="ok" transaction_id="1"/>\0
```

### Common Commands

| Command | Direction | Purpose |
|---------|-----------|---------|
| `run` | Client→Server | Resume execution |
| `step_into` | Client→Server | Step into function |
| `step_over` | Client→Server | Step over line |
| `step_out` | Client→Server | Step out of function |
| `break` | Client→Server | Pause execution |
| `stop` | Client→Server | Stop debugging |
| `breakpoint_set` | Client→Server | Set breakpoint |
| `property_get` | Client→Server | Get variable value |
| `context_get` | Client→Server | Get all variables |
| `stack_get` | Client→Server | Get call stack |

### Common Responses

| Response | Status | Reason | Meaning |
|----------|--------|--------|---------|
| `response` | `break` | `ok` | Execution paused |
| `response` | `running` | `ok` | Execution resumed |
| `response` | `stopped` | `ok` | Debugging stopped |
| `response` | `break` | `exception` | Exception caught |
| `response` | `break` | `error` | Error occurred |

## MCP Integration

### Tools Provided

```json
{
  "tools": [
    {
      "name": "get_debug_events",
      "description": "Query cached debug events",
      "inputSchema": {
        "type": "object",
        "properties": {
          "command": {"type": "string"},
          "limit": {"type": "number"},
          "offset": {"type": "number"}
        }
      }
    },
    {
      "name": "get_breakpoints",
      "description": "List all breakpoints"
    },
    {
      "name": "get_stack_history",
      "description": "Get stack traces over time"
    },
    {
      "name": "search_events",
      "description": "Search events by criteria"
    }
  ]
}
```

### Resources Provided

```json
{
  "resources": [
    {
      "uri": "debug://events",
      "name": "All Debug Events",
      "mimeType": "application/json"
    },
    {
      "uri": "debug://breakpoints",
      "name": "Current Breakpoints",
      "mimeType": "application/json"
    },
    {
      "uri": "debug://stack-history",
      "name": "Stack History",
      "mimeType": "application/json"
    },
    {
      "uri": "debug://variables",
      "name": "Variable States",
      "mimeType": "application/json"
    }
  ]
}
```

## Performance Considerations

### Memory Usage

- **Event Cache**: ~1000 events × ~2KB per event = ~2MB
- **Indexes**: ~500KB (transaction_id, command, breakpoint_id maps)
- **Stack Snapshots**: ~100 snapshots × ~5KB = ~500KB
- **Total**: ~3-4MB typical usage

### CPU Usage

- **Parsing**: ~1ms per event (XML parsing)
- **Indexing**: ~0.1ms per event
- **Caching**: O(1) for circular buffer
- **Queries**: O(n) for linear search, O(1) for indexed lookups

### Network Usage

- **DBGp Protocol**: ~1-10KB per command/response
- **Typical Session**: 100-1000 events = 100KB-10MB
- **MCP Queries**: ~1-100KB per query

## Troubleshooting

### Issue: Debugger not connecting to proxy

**Solution**:
```bash
# Verify environment variables
echo %AHK_DEBUGGER_PROXY_HOST%
echo %AHK_DEBUGGER_PROXY_PORT%

# Verify proxy is running
netstat -an | findstr 9002

# Check firewall
netsh advfirewall firewall add rule name="AHK Debugger" dir=in action=allow protocol=tcp localport=9002
```

### Issue: Events not being cached

**Solution**:
```bash
# Verify CONFIG_DEBUGGER_LOGGING is defined
# Check ahk_debugger_events.log exists
# Verify file permissions

# Enable verbose logging
set AHK_DEBUGGER_LOG_LEVEL=DEBUG
```

### Issue: MCP server not responding

**Solution**:
```bash
# Check Node.js version (requires 14+)
node --version

# Verify dependencies installed
npm install

# Check server logs
node ahk-debugger-mcp-server.js 2>&1 | tee server.log
```

## Future Enhancements

1. **Real-time Streaming**: WebSocket support for live event streaming
2. **Persistent Storage**: SQLite database for long-term event storage
3. **Advanced Filtering**: Complex query language for event filtering
4. **Performance Profiling**: CPU/memory usage tracking
5. **Breakpoint Management**: Remote breakpoint creation/modification
6. **Variable Inspection**: Deep object inspection and modification
7. **Session Recording**: Record and replay debug sessions
8. **Integration**: Slack/Discord notifications, external logging services

## References

- [DBGp Protocol Specification](https://xdebug.org/docs-dbgp.php)
- [AutoHotkey v2 Documentation](https://www.autohotkey.com/docs/v2/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Xdebug Protocol Implementation](https://github.com/xdebug/xdebug)
