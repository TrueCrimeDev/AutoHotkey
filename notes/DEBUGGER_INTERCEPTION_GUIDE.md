# AutoHotkey v2 Debugger Port Interception Guide

## Overview

This guide explains how to intercept the AutoHotkey v2 DBGp (Debugger Protocol) communication and create an MCP server to cache debug events in real-time.

## Architecture Analysis

### Current Debugger Flow

Based on the source code analysis (`source/Debugger.cpp` and `source/Debugger.h`):

```
AutoHotkey Script
    ↓
Debugger::Connect() [line 2467]
    ↓
TCP Socket (SOCK_STREAM, IPPROTO_TCP)
    ↓
Debugger Client (IDE/VSCode)
```

**Key Socket Details:**
- **Protocol**: TCP/IP (SOCK_STREAM)
- **Default Port**: 9002 (configurable via environment variables)
- **Connection Type**: Outbound from AHK to debugger client
- **Message Format**: DBGp XML protocol with length-prefixed packets

### DBGp Protocol Structure

Each message follows this format:
```
[length]\0[<?xml version="1.0" encoding="UTF-8"?>][xml_data]\0
```

**Example:**
```
123\0<?xml version="1.0" encoding="UTF-8"?><response command="status" status="break" reason="ok" transaction_id="1"/>\0
```

## Interception Strategies

### Strategy 1: TCP Proxy (Recommended for MCP)

**Advantages:**
- Non-invasive (no source code modification needed)
- Can cache all traffic bidirectionally
- Works with any debugger client
- Easy to implement as MCP server

**Implementation:**
```
AutoHotkey Script
    ↓
Proxy Server (MCP) - Port 9002
    ├→ Cache/Log all traffic
    └→ Forward to Real Debugger Client - Port 9003+
```

**Steps:**
1. Start MCP proxy on port 9002
2. Configure AHK to connect to localhost:9002
3. Proxy forwards to actual debugger on different port
4. All messages cached in MCP resource

### Strategy 2: Socket Hooking (Advanced)

**Advantages:**
- Direct access to socket operations
- Can modify messages in-flight
- No separate proxy needed

**Implementation Points in Source:**
- [`Debugger::Connect()` line 2467](source/Debugger.cpp:2467) - Initial connection
- [`Debugger::ReceiveCommand()` line 2389](source/Debugger.cpp:2389) - Incoming commands
- [`Debugger::SendResponse()` line 2427](source/Debugger.cpp:2427) - Outgoing responses

**Modification Approach:**
```cpp
// In Debugger::SendResponse() - line 2427
int Debugger::SendResponse(size_t aStartOffset)
{
    // INTERCEPTION POINT: Log response before sending
    LogDebugEvent("RESPONSE", mResponseBuf.mData + aStartOffset,
                  mResponseBuf.mDataUsed - aStartOffset);

    // Original code continues...
    // send(mSocket, response_header, ...);
}
```

### Strategy 3: Environment Variable Redirection

**Advantages:**
- Minimal code changes
- Works with existing infrastructure

**Implementation:**
```cpp
// In Debugger::Connect() - line 2467
int Debugger::Connect(const char *aAddress, const char *aPort)
{
    // Check for proxy environment variable
    const char *proxy_host = getenv("AHK_DEBUGGER_PROXY_HOST");
    const char *proxy_port = getenv("AHK_DEBUGGER_PROXY_PORT");

    if (proxy_host && proxy_port) {
        aAddress = proxy_host;
        aPort = proxy_port;
    }
    // Continue with connection...
}
```

## MCP Server Implementation

### Architecture

```
MCP Server (Node.js/Python)
├── TCP Proxy Layer
│   ├── Listen on port 9002
│   ├── Accept AHK connection
│   └── Forward to real debugger
├── Event Cache
│   ├── Store all DBGp messages
│   ├── Parse XML responses
│   └── Index by transaction_id
└── MCP Resources
    ├── /debug/events - All cached events
    ├── /debug/breakpoints - Current breakpoints
    ├── /debug/stack - Call stack snapshots
    └── /debug/variables - Variable states
```

### Key Components

#### 1. TCP Proxy

```javascript
const net = require('net');

class DebuggerProxy {
  constructor(listenPort = 9002, targetPort = 9003) {
    this.listenPort = listenPort;
    this.targetPort = targetPort;
    this.eventCache = [];
    this.connections = new Map();
  }

  start() {
    const server = net.createServer((ahkSocket) => {
      // Connect to real debugger
      const debuggerSocket = net.createConnection({
        host: 'localhost',
        port: this.targetPort
      });

      // Bidirectional forwarding with caching
      ahkSocket.on('data', (data) => {
        this.cacheEvent('AHK_TO_DEBUGGER', data);
        debuggerSocket.write(data);
      });

      debuggerSocket.on('data', (data) => {
        this.cacheEvent('DEBUGGER_TO_AHK', data);
        ahkSocket.write(data);
      });

      // Handle disconnections
      ahkSocket.on('end', () => debuggerSocket.end());
      debuggerSocket.on('end', () => ahkSocket.end());
    });

    server.listen(this.listenPort);
  }

  cacheEvent(direction, data) {
    const event = {
      timestamp: new Date().toISOString(),
      direction,
      rawData: data.toString('utf8'),
      size: data.length
    };
    this.eventCache.push(event);

    // Parse DBGp XML if applicable
    if (data.includes('<?xml')) {
      event.parsed = this.parseDBGp(data);
    }
  }

  parseDBGp(data) {
    // Extract XML from DBGp format: length\0<?xml...>\0
    const match = data.toString().match(/<?xml[^>]*>.*?<\/[^>]+>/s);
    if (match) {
      return {
        xml: match[0],
        // Parse command, status, transaction_id, etc.
      };
    }
  }
}
```

#### 2. Event Cache with Indexing

```javascript
class EventCache {
  constructor() {
    this.events = [];
    this.byTransactionId = new Map();
    this.byCommand = new Map();
    this.breakpoints = new Map();
    this.stackSnapshots = [];
  }

  addEvent(event) {
    this.events.push(event);

    // Index by transaction_id
    if (event.transactionId) {
      this.byTransactionId.set(event.transactionId, event);
    }

    // Index by command
    if (event.command) {
      if (!this.byCommand.has(event.command)) {
        this.byCommand.set(event.command, []);
      }
      this.byCommand.get(event.command).push(event);
    }

    // Track breakpoints
    if (event.command === 'breakpoint_set') {
      this.breakpoints.set(event.breakpointId, event);
    }

    // Snapshot stack on breaks
    if (event.status === 'break') {
      this.stackSnapshots.push({
        timestamp: event.timestamp,
        stack: event.stack
      });
    }
  }

  getEventsByCommand(command) {
    return this.byCommand.get(command) || [];
  }

  getEventsByTransactionId(id) {
    return this.byTransactionId.get(id);
  }

  getBreakpoints() {
    return Array.from(this.breakpoints.values());
  }

  getStackHistory() {
    return this.stackSnapshots;
  }
}
```

#### 3. MCP Resource Endpoints

```javascript
// MCP Server Resources
const resources = {
  'debug://events': {
    description: 'All cached debug events',
    mimeType: 'application/json',
    read: () => JSON.stringify(eventCache.events, null, 2)
  },

  'debug://breakpoints': {
    description: 'Current breakpoints',
    mimeType: 'application/json',
    read: () => JSON.stringify(eventCache.getBreakpoints(), null, 2)
  },

  'debug://stack-history': {
    description: 'Stack snapshots over time',
    mimeType: 'application/json',
    read: () => JSON.stringify(eventCache.getStackHistory(), null, 2)
  },

  'debug://variables': {
    description: 'Variable states from last break',
    mimeType: 'application/json',
    read: () => {
      const lastBreak = eventCache.events
        .reverse()
        .find(e => e.status === 'break');
      return JSON.stringify(lastBreak?.variables || {}, null, 2);
    }
  },

  'debug://errors': {
    description: 'All error events',
    mimeType: 'application/json',
    read: () => JSON.stringify(
      eventCache.getEventsByCommand('error'),
      null, 2
    )
  }
};
```

## Setup Instructions

### Option A: Using TCP Proxy (Easiest)

**1. Create MCP Server:**
```bash
npm init -y
npm install net
# Create proxy-server.js (see code above)
```

**2. Start Proxy:**
```bash
node proxy-server.js
# Listens on 9002, forwards to 9003
```

**3. Start Real Debugger Client:**
```bash
# In separate terminal, start your IDE debugger on port 9003
# Example: VSCode debug adapter on 9003
```

**4. Configure AutoHotkey:**
```autohotkey
; Set environment variables before running script
EnvSet("DBGP_IDEKEY", "autohotkey")
EnvSet("DBGP_COOKIE", "session123")

; Run with /Debug flag pointing to proxy
; AutoHotkey.exe /Debug 127.0.0.1:9002 script.ahk
```

### Option B: Source Code Modification (More Control)

**1. Modify `source/Debugger.cpp`:**

Add logging function after line 2461:
```cpp
void LogDebugEvent(const char *direction, const char *data, size_t size)
{
    FILE *f = fopen("C:\\debug_events.log", "ab");
    if (f) {
        fprintf(f, "[%s] %.*s\n", direction, (int)size, data);
        fclose(f);
    }
}
```

Modify `SendResponse()` at line 2427:
```cpp
int Debugger::SendResponse(size_t aStartOffset)
{
    // Log before sending
    LogDebugEvent("SEND", mResponseBuf.mData + aStartOffset,
                  mResponseBuf.mDataUsed - aStartOffset);

    // Original code...
    ASSERT(!mResponseBuf.mFailed);
    // ... rest of function
}
```

Modify `ReceiveCommand()` at line 2389:
```cpp
int Debugger::ReceiveCommand(int *aCommandLength)
{
    // ... existing code ...

    // After receiving data:
    if (bytes_received > 0) {
        LogDebugEvent("RECV", mCommandBuf.mData + mCommandBuf.mDataUsed - bytes_received,
                      bytes_received);
    }
}
```

**2. Recompile AutoHotkey:**
```bash
cd source
msbuild AutoHotkeyx.vcxproj /p:Configuration=Release
```

## DBGp Protocol Reference

### Common Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `status` | Get debugger status | `status -i 1` |
| `run` | Continue execution | `run -i 2` |
| `step_into` | Step into function | `step_into -i 3` |
| `step_over` | Step over line | `step_over -i 4` |
| `breakpoint_set` | Set breakpoint | `breakpoint_set -t line -f file:///path -n 10 -i 5` |
| `property_get` | Get variable value | `property_get -n varname -i 6` |
| `context_get` | Get all variables | `context_get -c 0 -d 0 -i 7` |

### Response Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<response command="status" status="break" reason="ok" transaction_id="1"/>
```

**Status Values:**
- `starting` - Script initializing
- `break` - Paused at breakpoint
- `running` - Executing
- `stopped` - Script ended

**Reason Values:**
- `ok` - Normal operation
- `error` - Error occurred
- `exception` - Exception thrown
- `breakpoint` - Hit breakpoint

## Caching Strategy

### What to Cache

1. **All Commands** - Track what debugger client requests
2. **All Responses** - Store results for analysis
3. **Breakpoint Events** - When set/removed/hit
4. **Stack Snapshots** - On each break
5. **Variable States** - When requested
6. **Error Events** - All exceptions/errors

### Cache Storage

```javascript
{
  timestamp: "2025-10-20T23:18:00Z",
  direction: "DEBUGGER_TO_AHK",
  command: "status",
  transactionId: "1",
  status: "break",
  reason: "breakpoint",
  rawData: "...",
  parsed: {
    // Parsed XML structure
  }
}
```

### Query Examples

```javascript
// Get all breakpoint events
cache.getEventsByCommand('breakpoint_set');

// Get response for specific transaction
cache.getEventsByTransactionId('42');

// Get stack history
cache.getStackHistory();

// Get all errors
cache.getEventsByCommand('error');
```

## Troubleshooting

### Issue: "Failed to connect to debugger"

**Solution:** Ensure proxy is running on correct port
```bash
netstat -ano | findstr :9002
```

### Issue: Proxy not receiving data

**Solution:** Check AutoHotkey is configured to use proxy
```autohotkey
; Verify connection
MsgBox(A_Args[1])  ; Should show proxy address
```

### Issue: XML parsing errors

**Solution:** DBGp format includes length prefix - strip it first
```javascript
const stripDBGpHeader = (data) => {
  const nullIndex = data.indexOf('\0');
  return data.substring(nullIndex + 1);
};
```

## Performance Considerations

- **Memory**: Cache grows with session length - implement rotation
- **Disk I/O**: Log to memory first, flush periodically
- **Network**: Proxy adds minimal latency (~1-2ms)
- **CPU**: XML parsing is negligible for typical debug sessions

## Security Notes

- Proxy should only listen on localhost (127.0.0.1)
- Don't expose debug port to network
- Cache may contain sensitive variable values
- Implement access controls if sharing cache

## References

- [DBGp Protocol Specification](https://xdebug.org/docs-dbgp.php)
- [AutoHotkey Debugger Source](source/Debugger.cpp)
- [Socket Programming (Winsock2)](https://docs.microsoft.com/en-us/windows/win32/winsock/winsock-functions)

## Next Steps

1. Choose interception strategy (TCP Proxy recommended)
2. Implement MCP server with event cache
3. Test with simple AHK script
4. Expand cache with additional event types
5. Build analysis tools on top of cache
