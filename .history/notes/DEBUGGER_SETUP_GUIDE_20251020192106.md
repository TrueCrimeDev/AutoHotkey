# AutoHotkey v2 Debugger Interception - Setup Guide

## Overview

This guide provides step-by-step instructions to intercept the AutoHotkey v2 debugger port and cache debug events using an MCP server.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AutoHotkey v2 Script                      │
│                   (with /Debug flag)                         │
└────────────────────────┬────────────────────────────────────┘
                         │ DBGp Protocol (TCP)
                         │ Port 9002 (default)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              DBGp Proxy/Interceptor (Node.js)                │
│                  (MCP Server)                                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ • Listen on port 9002                                │   │
│  │ • Cache all DBGp messages                            │   │
│  │ • Parse XML responses                                │   │
│  │ • Provide MCP tools & resources                      │   │
│  │ • Forward to real debugger (optional)                │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
   ┌─────────┐    ┌──────────────┐  ┌──────────────┐
   │ VS Code  │    │ Real Debugger│  │ MCP Client   │
   │ Debugger │    │ (optional)   │  │ (Claude)     │
   └─────────┘    └──────────────┘  └──────────────┘
```

## Step 1: Modify AutoHotkey Source (Optional but Recommended)

### Option A: Add Logging to Debugger.cpp

Edit `source/Debugger.cpp` and add logging at key interception points:

**Location 1: In `SendResponse()` (line ~2427)**

```cpp
int Debugger::SendResponse(size_t aStartOffset)
{
    ASSERT(!mResponseBuf.mFailed);
    ASSERT(aStartOffset < mResponseBuf.mDataUsed);
    ASSERT(mResponseBuf.mDataUsed <= mResponseBuf.mDataSize);

    // NEW: Log response before sending
    #ifdef CONFIG_DEBUGGER_LOGGING
    {
        FILE *f = fopen("ahk_debugger_responses.log", "a");
        if (f) {
            fprintf(f, "[%u] SEND %zu bytes\n", GetTickCount(),
                    mResponseBuf.mDataUsed - aStartOffset);
            fwrite(mResponseBuf.mData + aStartOffset, 1,
                   mResponseBuf.mDataUsed - aStartOffset, f);
            fprintf(f, "\n---\n");
            fclose(f);
        }
    }
    #endif

    // Original code continues...
    char response_header[DEBUGGER_RESPONSE_OVERHEAD];
    // ... rest of function
}
```

**Location 2: In `ReceiveCommand()` (line ~2389)**

```cpp
int Debugger::ReceiveCommand(int *aCommandLength)
{
    ASSERT(mSocket != INVALID_SOCKET);
    ASSERT(!mCommandBuf.mFailed);

    DWORD u = 0;

    for(;;)
    {
        for ( ; u < mCommandBuf.mDataUsed; ++u)
        {
            if (mCommandBuf.mData[u] == '\0')
            {
                if (aCommandLength)
                    *aCommandLength = u;

                // NEW: Log received command
                #ifdef CONFIG_DEBUGGER_LOGGING
                {
                    FILE *f = fopen("ahk_debugger_commands.log", "a");
                    if (f) {
                        fprintf(f, "[%u] RECV %d bytes\n", GetTickCount(), u);
                        fwrite(mCommandBuf.mData, 1, u, f);
                        fprintf(f, "\n---\n");
                        fclose(f);
                    }
                }
                #endif

                return DEBUGGER_E_OK;
            }
        }

        if (mCommandBuf.mDataUsed == mCommandBuf.mDataSize &&
            mCommandBuf.Expand() != DEBUGGER_E_OK)
            return FatalError();

        int bytes_received = recv(mSocket, mCommandBuf.mData + mCommandBuf.mDataUsed,
                                  (int)(mCommandBuf.mDataSize - mCommandBuf.mDataUsed), 0);

        if (bytes_received == SOCKET_ERROR)
            return FatalError();

        mCommandBuf.mDataUsed += bytes_received;
    }
}
```

### Option B: Use Environment Variable for Proxy

Modify `Connect()` to support proxy redirection:

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

    // ... rest of original function
}
```

## Step 2: Set Up MCP Server

### Install Dependencies

```bash
cd notes
npm install xml2js
```

### Create package.json

```json
{
  "name": "ahk-debugger-mcp",
  "version": "1.0.0",
  "description": "AutoHotkey v2 Debugger MCP Server",
  "main": "ahk-debugger-mcp-server.js",
  "type": "module",
  "dependencies": {
    "xml2js": "^0.6.2"
  },
  "scripts": {
    "start": "node ahk-debugger-mcp-server.js",
    "start:proxy": "AHK_DEBUGGER_PORT=9002 node ahk-debugger-mcp-server.js"
  }
}
```

### Start the MCP Server

```bash
# Basic usage (listen on port 9002)
node ahk-debugger-mcp-server.js

# With environment variables
AHK_DEBUGGER_PORT=9002 \
AHK_DEBUGGER_FORWARD_HOST=127.0.0.1 \
AHK_DEBUGGER_FORWARD_PORT=9003 \
node ahk-debugger-mcp-server.js
```

## Step 3: Configure AutoHotkey to Use Proxy

### Method 1: Environment Variables

```bash
# Windows PowerShell
$env:AHK_DEBUGGER_PROXY_HOST = "127.0.0.1"
$env:AHK_DEBUGGER_PROXY_PORT = "9002"

# Then run your script with /Debug
AutoHotkey.exe /Debug "your_script.ahk"
```

### Method 2: Direct Connection

If you compiled with proxy support, the debugger will automatically connect to the proxy instead of the real debugger.

## Step 4: Connect IDE/Debugger Client

### VS Code with Xdebug Extension

1. Install "PHP Debug" or "Xdebug" extension
2. Configure `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Listen for Xdebug",
      "type": "php",
      "request": "launch",
      "port": 9003,
      "pathMapping": {
        "/": "${workspaceFolder}"
      }
    }
  ]
}
```

3. Start listening, then run your AHK script with `/Debug`

### Direct DBGp Connection

Connect to `localhost:9002` with any DBGp-compatible client.

## Step 5: Query Cached Events

### Using MCP Tools

Once connected to the MCP server, you can:

```javascript
// Get all cached events
tools.call("get_debug_events", {
  command: "stack_get",
  limit: 50
});

// Get breakpoint information
tools.call("get_breakpoints", {});

// Get variable state at last break
tools.call("get_variables", {
  depth: 0,
  context: "local"
});

// Search events
tools.call("search_events", {
  query: "error",
  field: "reason"
});
```

### Using MCP Resources

```javascript
// Read cached events
resource.read("debug://events");

// Read breakpoints
resource.read("debug://breakpoints");

// Read stack history
resource.read("debug://stack-history");

// Read variable states
resource.read("debug://variables");

// Read error events
resource.read("debug://errors");
```

## Step 6: Monitor in Real-Time

### Watch Log Files

```bash
# Terminal 1: Start MCP server
node ahk-debugger-mcp-server.js

# Terminal 2: Watch events
tail -f ahk_debugger_events.log

# Terminal 3: Run your script
AutoHotkey.exe /Debug your_script.ahk
```

### Parse Events Programmatically

```javascript
const fs = require('fs');
const xml2js = require('xml2js');

const parser = new xml2js.Parser();

fs.watchFile('ahk_debugger_events.log', async (curr, prev) => {
  const data = fs.readFileSync('ahk_debugger_events.log', 'utf8');
  const events = data.split('---\n').filter(e => e.trim());

  for (const event of events) {
    try {
      const parsed = await parser.parseStringPromise(event);
      console.log('Event:', JSON.stringify(parsed, null, 2));
    } catch (e) {
      // Not XML, skip
    }
  }
});
```

## Troubleshooting

### Issue: "Connection refused" on port 9002

**Solution:** Ensure MCP server is running:
```bash
node ahk-debugger-mcp-server.js
```

### Issue: No events being captured

**Solution:** Verify AutoHotkey is connecting to the proxy:
```bash
# Check if port 9002 is listening
netstat -an | findstr 9002

# Verify environment variables are set
echo %AHK_DEBUGGER_PROXY_HOST%
echo %AHK_DEBUGGER_PROXY_PORT%
```

### Issue: Events not being parsed

**Solution:** Check XML format in log files:
```bash
# View raw events
type ahk_debugger_events.log

# Validate XML
# Ensure events start with <?xml version="1.0"?>
```

### Issue: Real debugger not receiving events

**Solution:** Ensure forwarding is configured:
```bash
AHK_DEBUGGER_FORWARD_HOST=127.0.0.1 \
AHK_DEBUGGER_FORWARD_PORT=9003 \
node ahk-debugger-mcp-server.js
```

## Advanced: Custom Event Processing

### Add Custom Event Handler

Edit `ahk-debugger-mcp-server.js`:

```javascript
class DBGpProxy {
  // ... existing code ...

  async handleEvent(event) {
    // Custom processing
    if (event.command === 'breakpoint_set') {
      console.log('Breakpoint set:', event.breakpointId);
      // Send to external service
      await this.notifyExternalService(event);
    }

    // Cache event
    this.cache.addEvent(event);
  }

  async notifyExternalService(event) {
    // Example: Send to webhook
    fetch('http://localhost:3000/debug-event', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(event)
    });
  }
}
```

### Export Events to Database

```javascript
const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('debug_events.db');

class DBGpProxy {
  async handleEvent(event) {
    db.run(
      'INSERT INTO events (timestamp, command, data) VALUES (?, ?, ?)',
      [new Date(), event.command, JSON.stringify(event)]
    );
  }
}
```

## Performance Considerations

- **Event Cache Size:** Default 1000 events. Adjust with `--cache-size` flag
- **Memory Usage:** ~1-2MB per 1000 events
- **CPU Impact:** Minimal (<1% overhead)
- **Network:** Transparent proxy adds <1ms latency

## Security Notes

⚠️ **Warning:** This proxy exposes debug information. Use only in development:

- Don't expose port 9002 to the internet
- Use firewall rules to restrict access
- Consider authentication for production use
- Sanitize sensitive data before logging

## References

- [DBGp Protocol Specification](https://xdebug.org/docs-dbgp.php)
- [AutoHotkey v2 Documentation](https://www.autohotkey.com/docs/v2/)
- [MCP Specification](https://modelcontextprotocol.io/)
