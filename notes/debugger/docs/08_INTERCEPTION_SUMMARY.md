# AutoHotkey v2 Debugger Interception - Complete Solution

## Overview

This document provides a complete solution for intercepting the AutoHotkey v2 native debugger's DBGp (Xdebug Protocol) traffic and translating it to an MCP server for caching and analyzing debug events in real-time.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AutoHotkey v2 Script                      │
│                   (with /Debug flag)                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ DBGp Protocol (TCP)
                         │ Port 9000 (default)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              AHK Debugger MCP Server (Node.js)              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  DBGp Proxy/Interceptor                              │  │
│  │  - Listens on port 9002                              │  │
│  │  - Forwards to real debugger (optional)              │  │
│  │  - Caches all events                                 │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Event Cache & Parser                                │  │
│  │  - Parses XML DBGp messages                          │  │
│  │  - Indexes by transaction_id, command, breakpoint   │  │
│  │  - Maintains stack history                           │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  MCP Tools & Resources                               │  │
│  │  - get_debug_events                                  │  │
│  │  - query_breakpoints                                 │  │
│  │  - get_stack_history                                 │  │
│  │  - debug://events resource                           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ MCP Protocol (stdio)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Claude / IDE Client                       │
│              (queries debug events via MCP)                  │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. DBGp Protocol Understanding

**Location in source:** [`source/Debugger.cpp`](../source/Debugger.cpp:2389-2461)

The AutoHotkey debugger uses the DBGp protocol (Xdebug Protocol) which operates as follows:

- **Connection:** TCP socket connection (default port 9000)
- **Message Format:** `<length>\0<xml_tag><xml_data>\0`
- **Commands:** `run`, `step_into`, `step_over`, `step_out`, `break`, `breakpoint_set`, `property_get`, etc.
- **Responses:** XML-formatted responses with transaction IDs

**Critical Functions:**
- [`Debugger::Connect()`](../source/Debugger.cpp:2467) - Establishes connection
- [`Debugger::ReceiveCommand()`](../source/Debugger.cpp:2389) - Receives DBGp commands
- [`Debugger::SendResponse()`](../source/Debugger.cpp:2427) - Sends DBGp responses
- [`Debugger::ProcessCommands()`](../source/Debugger.cpp:317) - Main command loop

### 2. Interception Points

#### Point A: Socket Connection (Line 2467)
```cpp
int Debugger::Connect(const char *aAddress, const char *aPort)
{
    // INTERCEPTION: Redirect to proxy
    const char *proxy_host = getenv("AHK_DEBUGGER_PROXY_HOST");
    const char *proxy_port = getenv("AHK_DEBUGGER_PROXY_PORT");

    if (proxy_host && proxy_port) {
        aAddress = proxy_host;
        aPort = proxy_port;
    }
    // ... rest of function
}
```

#### Point B: Receive Commands (Line 2389)
```cpp
int Debugger::ReceiveCommand(int *aCommandLength)
{
    // ... existing code ...

    // INTERCEPTION: Log received command
    if (bytes_received > 0) {
        LogDebugEvent("RECV", mCommandBuf.mData + mCommandBuf.mDataUsed - bytes_received,
                      bytes_received);
    }
}
```

#### Point C: Send Responses (Line 2427)
```cpp
int Debugger::SendResponse(size_t aStartOffset)
{
    // INTERCEPTION: Log response before sending
    LogDebugEvent("SEND", mResponseBuf.mData + aStartOffset,
                  mResponseBuf.mDataUsed - aStartOffset);

    // ... rest of function
}
```

### 3. Implementation Strategy

#### Option A: Environment Variable Redirection (Minimal Changes)

**Pros:**
- Requires only 3-4 lines of code change
- No recompilation needed if using environment variables
- Works with existing debugger infrastructure

**Cons:**
- Requires proxy to forward to real debugger
- Adds network hop

**Implementation:**
```cpp
// In Debugger::Connect() around line 2467
const char *proxy_host = getenv("AHK_DEBUGGER_PROXY_HOST");
const char *proxy_port = getenv("AHK_DEBUGGER_PROXY_PORT");

if (proxy_host && proxy_port) {
    aAddress = proxy_host;
    aPort = proxy_port;
}
```

#### Option B: Logging to File (Moderate Changes)

**Pros:**
- No network overhead
- Can analyze offline
- Works with any debugger client

**Cons:**
- Requires file I/O
- Slight performance impact
- Need to parse log files

**Implementation:**
```cpp
// Add to Debugger class
void LogDebugEvent(const char *aType, const char *aData, size_t aSize)
{
    #ifdef CONFIG_DEBUGGER_LOGGING
    {
        FILE *f = fopen("ahk_debugger_events.log", "a");
        if (f) {
            fprintf(f, "[%u] %s %zu bytes\n", GetTickCount(), aType, aSize);
            fwrite(aData, 1, aSize, f);
            fprintf(f, "\n---\n");
            fclose(f);
        }
    }
    #endif
}
```

#### Option C: Named Pipe Communication (Advanced)

**Pros:**
- Real-time streaming
- No file I/O overhead
- Bidirectional communication possible

**Cons:**
- More complex implementation
- Windows-specific (or requires cross-platform abstraction)
- Requires separate listener process

**Implementation:**
```cpp
// In Debugger class
HANDLE mEventPipe = INVALID_HANDLE_VALUE;

void LogEventToPipe(const char *aType, const char *aData, size_t aSize)
{
    if (mEventPipe == INVALID_HANDLE_VALUE) return;

    char header[64];
    int header_len = sprintf(header, "[%s:%zu:", aType, aSize);

    DWORD written;
    WriteFile(mEventPipe, header, header_len, &written, NULL);
    WriteFile(mEventPipe, aData, aSize, &written, NULL);
    WriteFile(mEventPipe, "]\n", 2, &written, NULL);
}
```

## MCP Server Implementation

### Setup

```bash
# Install dependencies
npm install xml2js

# Run the server
node ahk-debugger-mcp-server.js --port 9002

# Or with environment variables
AHK_DEBUGGER_PORT=9002 \
AHK_DEBUGGER_FORWARD_HOST=127.0.0.1 \
AHK_DEBUGGER_FORWARD_PORT=9000 \
node ahk-debugger-mcp-server.js
```

### Available Tools

#### 1. `get_debug_events`
Query cached debug events with filtering

```json
{
  "command": "get_debug_events",
  "arguments": {
    "command": "breakpoint_set",
    "limit": 50,
    "offset": 0
  }
}
```

#### 2. `query_breakpoints`
Get all breakpoints and their states

```json
{
  "command": "query_breakpoints",
  "arguments": {}
}
```

#### 3. `get_stack_history`
Retrieve stack snapshots over time

```json
{
  "command": "get_stack_history",
  "arguments": {
    "limit": 10
  }
}
```

#### 4. `search_events`
Full-text search across cached events

```json
{
  "command": "search_events",
  "arguments": {
    "query": "error",
    "limit": 20
  }
}
```

### Available Resources

- `debug://events` - All cached debug events (JSON)
- `debug://breakpoints` - Current breakpoints
- `debug://stack-history` - Stack snapshots
- `debug://variables` - Last known variable states
- `debug://errors` - All error events

## Usage Workflow

### Step 1: Modify AutoHotkey Source

Choose one of the three implementation options above and apply the changes to `source/Debugger.cpp`.

### Step 2: Recompile AutoHotkey

```bash
# In Visual Studio or command line
msbuild AutoHotkeyx.vcxproj /p:Configuration=Release /p:Platform=x64
```

### Step 3: Start MCP Server

```bash
node ahk-debugger-mcp-server.js --port 9002
```

### Step 4: Configure AutoHotkey Script

For **Option A (Environment Variable Redirection):**
```batch
set AHK_DEBUGGER_PROXY_HOST=127.0.0.1
set AHK_DEBUGGER_PROXY_PORT=9002
AutoHotkey.exe /Debug myscript.ahk
```

For **Option B (File Logging):**
```batch
# Just run normally, logs go to ahk_debugger_events.log
AutoHotkey.exe /Debug myscript.ahk
```

### Step 5: Query via MCP

```javascript
// Example: Get all breakpoint events
const response = await mcpClient.callTool('get_debug_events', {
  command: 'breakpoint_set',
  limit: 100
});

console.log(response.events);
```

## Event Cache Structure

```javascript
{
  timestamp: 1634567890123,
  type: 'response',
  command: 'breakpoint_set',
  transactionId: '1',
  status: 'break',
  reason: 'ok',
  breakpointId: 1,
  filename: 'file:///C:/script.ahk',
  lineno: 42,
  state: 'enabled',
  rawData: '<response command="breakpoint_set" .../>',
  parsed: {
    // Parsed XML structure
  }
}
```

## Troubleshooting

### Issue: "Connection refused" on port 9002

**Solution:** Ensure MCP server is running and listening:
```bash
netstat -an | findstr 9002
```

### Issue: Events not being captured

**Solution:** Verify environment variables are set:
```batch
echo %AHK_DEBUGGER_PROXY_HOST%
echo %AHK_DEBUGGER_PROXY_PORT%
```

### Issue: XML parsing errors

**Solution:** Check that DBGp messages are complete:
```bash
# Monitor log file in real-time
tail -f ahk_debugger_events.log
```

### Issue: Performance degradation

**Solution:** Reduce cache size or implement event filtering:
```javascript
const proxy = new DBGpProxy(9002, null, null, {
  maxCacheSize: 500,  // Reduce from 1000
  filterCommands: ['property_get']  // Only cache specific commands
});
```

## Advanced: Custom Event Handlers

Extend the MCP server to handle custom events:

```javascript
class CustomEventHandler {
  onBreakpoint(event) {
    console.log(`Breakpoint hit at ${event.filename}:${event.lineno}`);
    // Send to external service
    this.notifySlack(`Debug breakpoint: ${event.filename}:${event.lineno}`);
  }

  onError(event) {
    console.log(`Error: ${event.error}`);
    // Log to external service
    this.logToSentry(event);
  }
}
```

## Performance Considerations

| Aspect | Impact | Mitigation |
|--------|--------|-----------|
| Memory | Cache grows with events | Implement circular buffer, limit size |
| CPU | XML parsing overhead | Use streaming parser, batch processing |
| Network | Proxy adds latency | Use local proxy, minimize forwarding |
| Disk I/O | File logging is slow | Use async I/O, batch writes |

## Security Considerations

1. **Port Access:** Restrict MCP server to localhost only
2. **Event Data:** May contain sensitive variable values
3. **File Permissions:** Ensure log files are not world-readable
4. **Network:** Use firewall rules to restrict debugger port access

## References

- **DBGp Protocol:** https://xdebug.org/docs-dbgp.php
- **AutoHotkey Source:** `source/Debugger.cpp`, `source/Debugger.h`
- **MCP Specification:** https://modelcontextprotocol.io/

## Files Created

1. **`notes/DEBUGGER_INTERCEPTION_GUIDE.md`** - Detailed technical guide
2. **`notes/ahk-debugger-mcp-server.js`** - Complete MCP server implementation
3. **`notes/DEBUGGER_MODIFICATION_IMPLEMENTATION.md`** - C++ modification details
4. **`notes/DEBUGGER_SETUP_GUIDE.md`** - Step-by-step setup instructions
5. **`notes/DEBUGGER_INTERCEPTION_SUMMARY.md`** - This file

## Next Steps

1. Choose implementation option (A, B, or C)
2. Apply modifications to `source/Debugger.cpp`
3. Recompile AutoHotkey
4. Deploy MCP server
5. Test with sample scripts
6. Integrate with your debugging workflow
