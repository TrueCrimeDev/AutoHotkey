# AutoHotkey v2 Debugger Interception - Implementation Guide

## Overview

This guide provides step-by-step instructions to modify the AutoHotkey v2 debugger to intercept and cache debug events through an MCP server or proxy.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AutoHotkey v2 Script                      │
└────────────────────────┬────────────────────────────────────┘
                         │ /Debug flag
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              AutoHotkey v2 Debugger Engine                   │
│  (source/Debugger.cpp - Debugger::Connect/SendResponse)     │
└────────────────────────┬────────────────────────────────────┘
                         │ TCP Socket (DBGp Protocol)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│         DBGp Proxy/MCP Server (Node.js)                      │
│  - Intercepts all DBGp traffic                              │
│  - Caches events in memory                                  │
│  - Provides MCP tools & resources                           │
│  - Forwards to real IDE (optional)                          │
└────────────────────────┬────────────────────────────────────┘
                         │ (Optional forwarding)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              IDE/Debugger Client (VSCode, etc)              │
└─────────────────────────────────────────────────────────────┘
```

## Method 1: Proxy Interception (Recommended - No C++ Changes)

### Setup

1. **Start the MCP Server:**
```bash
cd notes
npm install xml2js
node ahk-debugger-mcp-server.js --port 9002
```

2. **Configure AutoHotkey to use proxy:**
```autohotkey
; In your AHK v2 script
#Requires AutoHotkey v2.0
#Debug "127.0.0.1:9002"  ; Connect to proxy instead of IDE

; Your script code...
```

3. **Access cached events via MCP:**
```bash
# Query events
curl http://localhost:3000/tools/query-events \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"command": "breakpoint_set", "limit": 50}'

# Get stack history
curl http://localhost:3000/resources/debug://stack-history
```

### Advantages
- ✅ No C++ compilation needed
- ✅ Works with existing AutoHotkey builds
- ✅ Easy to deploy and test
- ✅ Can forward to real IDE simultaneously
- ✅ Full event caching and analysis

## Method 2: Direct C++ Modification (Advanced)

### Step 1: Add Logging Infrastructure

**File: `source/Debugger.h`** (after line 265)

```cpp
private:
    // Debug event logging
    struct DebugEvent {
        const char *type;      // "SEND", "RECV", "COMMAND", "ERROR"
        const char *data;
        size_t size;
        DWORD timestamp;
    };

    // Event cache
    static const int MAX_CACHED_EVENTS = 1000;
    DebugEvent mEventCache[MAX_CACHED_EVENTS];
    int mEventCacheIndex = 0;

    void LogDebugEvent(const char *aType, const char *aData, size_t aSize);
    void DumpEventCache(const char *aFilePath);
```

### Step 2: Implement Logging Functions

**File: `source/Debugger.cpp`** (add after line 3240)

```cpp
void Debugger::LogDebugEvent(const char *aType, const char *aData, size_t aSize)
{
#ifdef CONFIG_DEBUGGER_LOGGING
    if (mEventCacheIndex >= MAX_CACHED_EVENTS)
        mEventCacheIndex = 0; // Circular buffer

    DebugEvent &event = mEventCache[mEventCacheIndex++];
    event.type = aType;
    event.data = aData;
    event.size = aSize;
    event.timestamp = GetTickCount();

    // Optional: Write to file for real-time monitoring
    static FILE *log_file = nullptr;
    if (!log_file) {
        log_file = fopen("ahk_debugger_events.log", "a");
    }
    if (log_file) {
        fprintf(log_file, "[%u] %s: %.*s\n", event.timestamp, aType, (int)aSize, aData);
        fflush(log_file);
    }
#endif
}

void Debugger::DumpEventCache(const char *aFilePath)
{
#ifdef CONFIG_DEBUGGER_LOGGING
    FILE *f = fopen(aFilePath, "w");
    if (!f) return;

    fprintf(f, "[\n");
    for (int i = 0; i < mEventCacheIndex; ++i) {
        DebugEvent &e = mEventCache[i];
        fprintf(f, "  {\n");
        fprintf(f, "    \"type\": \"%s\",\n", e.type);
        fprintf(f, "    \"timestamp\": %u,\n", e.timestamp);
        fprintf(f, "    \"size\": %zu,\n", e.size);
        fprintf(f, "    \"data\": \"");
        // Escape JSON
        for (size_t j = 0; j < e.size && j < 500; ++j) {
            char c = e.data[j];
            if (c == '"') fprintf(f, "\\\"");
            else if (c == '\\') fprintf(f, "\\\\");
            else if (c == '\n') fprintf(f, "\\n");
            else if (c == '\r') fprintf(f, "\\r");
            else if (c >= 32 && c < 127) fprintf(f, "%c", c);
            else fprintf(f, "\\x%02x", (unsigned char)c);
        }
        fprintf(f, "\"\n");
        fprintf(f, "  }%s\n", i < mEventCacheIndex - 1 ? "," : "");
    }
    fprintf(f, "]\n");
    fclose(f);
#endif
}
```

### Step 3: Hook into SendResponse

**File: `source/Debugger.cpp`** (modify line 2427)

```cpp
int Debugger::SendResponse(size_t aStartOffset)
{
    ASSERT(!mResponseBuf.mFailed);
    ASSERT(aStartOffset < mResponseBuf.mDataUsed);
    ASSERT(mResponseBuf.mDataUsed <= mResponseBuf.mDataSize);

    // LOG: Capture response before sending
    LogDebugEvent("SEND", mResponseBuf.mData + aStartOffset,
                  mResponseBuf.mDataUsed - aStartOffset);

    char response_header[DEBUGGER_RESPONSE_OVERHEAD];

    // ... rest of original function ...
}
```

### Step 4: Hook into ReceiveCommand

**File: `source/Debugger.cpp`** (modify line 2414)

```cpp
int Debugger::ReceiveCommand(int *aCommandLength)
{
    ASSERT(mSocket != INVALID_SOCKET);
    ASSERT(!mCommandBuf.mFailed);

    DWORD u = 0;

    for(;;)
    {
        // Check data received in the previous iteration or by a previous call to ReceiveCommand().
        for ( ; u < mCommandBuf.mDataUsed; ++u)
        {
            if (mCommandBuf.mData[u] == '\0')
            {
                if (aCommandLength)
                    *aCommandLength = u;

                // LOG: Capture received command
                LogDebugEvent("RECV", mCommandBuf.mData, u);

                return DEBUGGER_E_OK;
            }
        }

        // Init or expand the buffer as necessary.
        if (mCommandBuf.mDataUsed == mCommandBuf.mDataSize && mCommandBuf.Expand() != DEBUGGER_E_OK)
            return FatalError();

        // Receive and append data.
        int bytes_received = recv(mSocket, mCommandBuf.mData + mCommandBuf.mDataUsed,
                                  (int)(mCommandBuf.mDataSize - mCommandBuf.mDataUsed), 0);

        if (bytes_received == SOCKET_ERROR)
            return FatalError();

        mCommandBuf.mDataUsed += bytes_received;
    }
}
```

### Step 5: Hook into ProcessCommands

**File: `source/Debugger.cpp`** (modify line 390)

```cpp
// EXECUTE THE DBGP COMMAND.
LogDebugEvent("COMMAND", command, strlen(command));
err = (this->*sCommands[i].mFunc)(argv, arg_count, transaction_id);
```

### Step 6: Compile with Logging Enabled

**File: `source/config.h`** (add after line 50)

```cpp
// Enable debugger event logging
#define CONFIG_DEBUGGER_LOGGING 1
```

**Build command:**
```bash
# Windows with Visual Studio
msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64

# Or with CMake if available
cmake -DCONFIG_DEBUGGER_LOGGING=ON -B build
cmake --build build --config Release
```

## Method 3: Environment Variable Proxy Redirect

**File: `source/Debugger.cpp`** (modify line 2467)

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

    // ... rest of original function ...
}
```

**Usage:**
```bash
# Set environment variables
set AHK_DEBUGGER_PROXY_HOST=127.0.0.1
set AHK_DEBUGGER_PROXY_PORT=9002

# Run AutoHotkey with /Debug flag
AutoHotkey.exe /Debug "127.0.0.1:9002" script.ahk
```

## Method 4: Named Pipe Interception (Windows-specific)

For even more control, use Windows Named Pipes:

**File: `source/Debugger.cpp`** (add after line 30)

```cpp
#include <windows.h>

// Named pipe for event logging
HANDLE g_DebugEventPipe = INVALID_HANDLE_VALUE;

void InitDebugEventPipe() {
    g_DebugEventPipe = CreateNamedPipeA(
        "\\\\.\\pipe\\ahk_debugger_events",
        PIPE_ACCESS_OUTBOUND,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
        1, 4096, 4096, 0, NULL
    );
}

void LogEventToPipe(const char *aType, const char *aData, size_t aSize) {
    if (g_DebugEventPipe == INVALID_HANDLE_VALUE) return;

    // Format: [TYPE:SIZE:DATA]
    char header[64];
    int header_len = sprintf(header, "[%s:%zu:", aType, aSize);

    DWORD written;
    WriteFile(g_DebugEventPipe, header, header_len, &written, NULL);
    WriteFile(g_DebugEventPipe, aData, aSize, &written, NULL);
    WriteFile(g_DebugEventPipe, "]\n", 2, &written, NULL);
}
```

## Testing the Implementation

### Test 1: Verify Event Logging

```autohotkey
#Requires AutoHotkey v2.0
#Debug "127.0.0.1:9002"

MsgBox("Breakpoint 1")
x := 42
MsgBox("Breakpoint 2")
```

### Test 2: Query Cached Events

```bash
# Get all events
curl http://localhost:3000/tools/query-events \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"limit": 100}'

# Get breakpoint events only
curl http://localhost:3000/tools/query-events \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"command": "breakpoint_set"}'

# Get stack history
curl http://localhost:3000/resources/debug://stack-history
```

### Test 3: Monitor Real-time Events

```bash
# Watch the log file
tail -f ahk_debugger_events.log

# Or query via MCP
watch -n 1 'curl -s http://localhost:3000/resources/debug://events | jq ".[-5:]"'
```

## Performance Considerations

1. **Circular Buffer**: Event cache uses circular buffer to prevent unbounded memory growth
2. **Lazy Parsing**: XML parsing only on demand
3. **Indexing**: Events indexed by transaction_id and command for O(1) lookup
4. **Compression**: Consider gzip for large event dumps

## Security Notes

- ⚠️ Debug port should only be exposed on localhost
- ⚠️ Event cache may contain sensitive variable values
- ⚠️ Use firewall rules to restrict access
- ⚠️ Consider authentication for production use

## Troubleshooting

### Events not being captured
- Verify proxy is listening: `netstat -an | grep 9002`
- Check AutoHotkey is connecting: `netstat -an | grep ESTABLISHED`
- Enable verbose logging in MCP server

### Memory usage growing
- Reduce cache size: `node ahk-debugger-mcp-server.js --cache-size 500`
- Implement event expiration
- Dump cache periodically

### Forwarding not working
- Verify IDE is listening on expected port
- Check firewall rules
- Enable debug logging in proxy

## References

- [DBGp Protocol Specification](https://xdebug.org/docs-dbgp.php)
- [AutoHotkey v2 Documentation](https://www.autohotkey.com/docs/v2/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
