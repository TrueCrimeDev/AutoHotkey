# AutoHotkey v2 Debugger Port Interception Guide

## Overview
This guide explains how to intercept the AutoHotkey v2 DBGp (Debugger Protocol) communication and create an MCP server to cache debug events in real-time.

## Architecture Analysis

### Current Debugger Flow
1. **Socket Connection** (`Debugger::Connect()` - line 2467)
   - Creates TCP socket on specified host/port
   - Uses Winsock2 for Windows socket communication
   - Default: `127.0.0.1:9002`

2. **Command Reception** (`Debugger::ReceiveCommand()` - line 2389)
   - Receives DBGp commands via `recv()` on the socket
   - Buffers commands in `mCommandBuf`
   - Processes commands in `ProcessCommands()` loop

3. **Response Transmission** (`Debugger::SendResponse()` - line 2427)
   - Sends XML responses via `send()` on the socket
   - Format: `[length]\0<?xml...?>[data]\0`

### Key Socket Operations
- **Line 2414**: `recv(mSocket, mCommandBuf.mData + mCommandBuf.mDataUsed, ...)`
- **Line 2451-2453**: `send(mSocket, response_header, ...)` and `send(mSocket, mResponseBuf.mData, ...)`
- **Line 348**: `WSAAsyncSelect()` for async socket notifications
- **Line 272**: `ioctlsocket(mSocket, FIONREAD, &dataPending)` for checking pending data

## Interception Strategies

### Strategy 1: Socket Proxy (Recommended)
Create a proxy server that:
1. Listens on the debugger port (9002)
2. Accepts connections from the IDE
3. Connects to the actual AHK debugger
4. Intercepts and logs all traffic bidirectionally
5. Caches events in real-time

**Advantages:**
- Non-invasive (no source code modification needed)
- Works with existing AHK builds
- Can be toggled on/off
- Supports multiple concurrent sessions

**Implementation:**
```
IDE Client → Proxy Server → AHK Debugger
                ↓
            Event Cache (MCP)
```

### Strategy 2: Winsock Hooking
Hook Winsock functions:
- `recv()` - intercept incoming commands
- `send()` - intercept outgoing responses
- `WSAAsyncSelect()` - monitor async events

**Advantages:**
- Direct access to all traffic
- No proxy overhead

**Disadvantages:**
- Requires DLL injection
- More complex implementation
- Platform-specific

### Strategy 3: Source Code Modification
Add logging hooks in `Debugger.cpp`:
- `ReceiveCommand()` - log received commands
- `SendResponse()` - log sent responses
- `ProcessCommands()` - log command processing

**Advantages:**
- Direct integration
- Full control

**Disadvantages:**
- Requires recompilation
- Modifies core debugger

## DBGp Protocol Structure

### Command Format
```
command_name -arg1 value1 -arg2 value2 ... -i transaction_id\0
```

### Response Format
```
[length]\0<?xml version="1.0" encoding="UTF-8"?><response .../>\0
```

### Common Commands
- `run`, `step_into`, `step_over`, `step_out` - execution control
- `breakpoint_set`, `breakpoint_remove` - breakpoint management
- `stack_get`, `context_get` - variable inspection
- `property_get`, `property_set` - property access

### Common Events
- `<response command="..." status="break" reason="ok"/>` - break event
- `<response command="..." status="stopped" reason="ok"/>` - stop event
- `<stream type="stdout">` - stdout redirection
- `<stream type="stderr">` - stderr redirection

## Implementation: Socket Proxy MCP Server

### Architecture
```
┌─────────────────────────────────────────────────────┐
│         AutoHotkey Debugger MCP Server              │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Socket Proxy (Port 9002)                    │  │
│  │  - Accepts IDE connections                   │  │
│  │  - Forwards to real debugger (9003)          │  │
│  │  - Intercepts all traffic                    │  │
│  └──────────────────────────────────────────────┘  │
│                      ↓                              │
│  ┌──────────────────────────────────────────────┐  │
│  │  Event Cache & Parser                        │  │
│  │  - Parse DBGp XML                            │  │
│  │  - Extract events (breaks, steps, etc)       │  │
│  │  - Store in memory cache                     │  │
│  │  - Maintain session state                    │  │
│  └──────────────────────────────────────────────┘  │
│                      ↓                              │
│  ┌──────────────────────────────────────────────┐  │
│  │  MCP Tools & Resources                       │  │
│  │  - get_debug_events()                        │  │
│  │  - get_breakpoint_hits()                     │  │
│  │  - get_variable_values()                     │  │
│  │  - get_stack_trace()                         │  │
│  │  - get_session_state()                       │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Key Components

#### 1. Socket Proxy
- Listen on port 9002 (IDE connection)
- Connect to port 9003 (real debugger)
- Bidirectional forwarding with interception

#### 2. DBGp Parser
- Parse XML responses
- Extract command/response pairs
- Track transaction IDs
- Identify event types

#### 3. Event Cache
- Store recent events (configurable limit)
- Track breakpoint hits
- Store variable snapshots
- Maintain execution state

#### 4. MCP Interface
- Expose cache via MCP tools
- Query events by type/time
- Filter by breakpoint/file/line
- Export session data

## Configuration

### Environment Variables
```
DBGP_PROXY_ENABLED=1          # Enable proxy
DBGP_PROXY_PORT=9002          # Proxy listen port
DBGP_REAL_PORT=9003           # Real debugger port
DBGP_CACHE_SIZE=1000          # Max cached events
DBGP_LOG_FILE=debug.log       # Optional logging
```

### AHK Launch Command
```
AutoHotkey.exe /Debug 127.0.0.1:9003 script.ahk
```

Then IDE connects to proxy on 9002 instead of 9003.

## Usage Example

### 1. Start Proxy
```bash
node ahk-debugger-proxy.js
```

### 2. Launch AHK with Debugger
```bash
AutoHotkey.exe /Debug 127.0.0.1:9003 script.ahk
```

### 3. Connect IDE to Proxy
Configure IDE to connect to `127.0.0.1:9002` instead of `9003`

### 4. Query Events via MCP
```json
{
  "method": "tools/call",
  "params": {
    "name": "get_debug_events",
    "arguments": {
      "type": "break",
      "limit": 10
    }
  }
}
```

## Benefits

1. **Non-Invasive**: Works with existing AHK builds
2. **Real-Time Caching**: Events cached as they occur
3. **Queryable**: MCP tools to access cached data
4. **Debuggable**: Can log all traffic for analysis
5. **Extensible**: Easy to add new event types
6. **Session Aware**: Tracks multiple debug sessions

## Limitations & Considerations

1. **Port Conflict**: Proxy needs different port than real debugger
2. **Performance**: Minimal overhead from interception
3. **Thread Safety**: Cache needs synchronization for concurrent access
4. **Memory**: Cache size should be configurable
5. **Cleanup**: Old events should be pruned

## Advanced Features

### 1. Event Filtering
- Filter by breakpoint ID
- Filter by file/line
- Filter by variable name
- Filter by time range

### 2. Event Export
- Export to JSON
- Export to CSV
- Export to SQLite
- Stream to external service

### 3. Replay
- Replay debug session
- Step through cached events
- Inspect historical state

### 4. Analysis
- Breakpoint hit frequency
- Variable change tracking
- Execution path analysis
- Performance profiling

## References

- DBGp Protocol: https://xdebug.org/docs-dbgp.php
- Winsock2: https://docs.microsoft.com/en-us/windows/win32/winsock/winsock-reference
- AutoHotkey Debugger: `source/Debugger.cpp` and `source/Debugger.h`
