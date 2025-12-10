# WinAPI Debugger Reference

This document explains how to use Windows API directly to create AutoHotkey v2 debugger clients.

## Why Use WinAPI Directly?

**Advantages:**
- ✓ No dependencies (Python, Node.js, etc.)
- ✓ Native Windows performance
- ✓ Full control over socket behavior
- ✓ Can be embedded in other C/C++ applications
- ✓ Smaller binaries (~20KB compiled)

**The DBGp protocol is just XML messages over TCP sockets - you can implement it yourself!**

## Core WinAPI Functions Used

### 1. Winsock Initialization

```cpp
#include <winsock2.h>
#pragma comment(lib, "ws2_32.lib")

WSADATA wsa;
WSAStartup(MAKEWORD(2,2), &wsa);  // Initialize Windows Sockets v2.2
```

**What it does:** Loads the Windows Sockets DLL into memory. Required before any socket operations.

### 2. Create Socket

```cpp
SOCKET sock = socket(AF_INET,      // IPv4
                     SOCK_STREAM,  // TCP
                     0);           // Protocol (auto)
```

**What it does:** Creates a TCP socket handle. This is your communication endpoint.

### 3. Bind to Port

```cpp
struct sockaddr_in server;
server.sin_family = AF_INET;
server.sin_addr.s_addr = inet_addr("127.0.0.1");  // Localhost
server.sin_port = htons(9000);                     // Port 9000

bind(sock, (struct sockaddr*)&server, sizeof(server));
```

**What it does:** Reserves port 9000 on localhost for your debugger. AutoHotkey will connect to this.

### 4. Listen for Connections

```cpp
listen(sock, 1);  // Allow 1 pending connection
```

**What it does:** Marks the socket as passive - it will wait for incoming connections.

### 5. Accept Connection

```cpp
SOCKET client = accept(sock, NULL, NULL);
```

**What it does:** Blocks until AutoHotkey connects. Returns a new socket for communicating with AHK.

### 6. Send Commands

```cpp
const char* command = "step_into -i 1\0";
send(client, command, strlen(command) + 1, 0);  // +1 for null terminator
```

**What it does:** Sends a DBGp command to AutoHotkey. Must include null terminator.

### 7. Receive Responses

```cpp
char buffer[8192];

// First read the length prefix (null-terminated ASCII number)
char lengthBuf[32];
int pos = 0;
while (pos < 32) {
    recv(client, &lengthBuf[pos], 1, 0);
    if (lengthBuf[pos] == '\0') break;
    pos++;
}
int msgLength = atoi(lengthBuf);

// Now read the actual XML message
int received = 0;
while (received < msgLength + 1) {
    int result = recv(client, buffer + received, msgLength + 1 - received, 0);
    received += result;
}
buffer[msgLength] = '\0';
```

**What it does:** Reads AutoHotkey's response. DBGp uses length-prefixed messages: `"125\0<xml...>\0"`

### 8. Cleanup

```cpp
closesocket(client);
closesocket(sock);
WSACleanup();
```

**What it does:** Closes sockets and unloads Winsock DLL.

## DBGp Protocol Format

All messages follow this format:

### Client → AutoHotkey (Commands)

```
command_name -option value -i transaction_id\0
```

Examples:
```cpp
"run -i 1\0"
"step_into -i 2\0"
"breakpoint_set -t line -n 10 -i 3\0"
"context_get -i 4\0"
"stack_get -i 5\0"
```

### AutoHotkey → Client (Responses)

```
byte_length\0<xml_response>\0
```

Example:
```
125\0<?xml version="1.0" encoding="UTF-8"?>
<response command="step_into" transaction_id="2" status="break" reason="ok" />
\0
```

## Complete Minimal Example

```cpp
#include <winsock2.h>
#include <stdio.h>

#pragma comment(lib, "ws2_32.lib")

int main() {
    // 1. Initialize Winsock
    WSADATA wsa;
    WSAStartup(MAKEWORD(2,2), &wsa);

    // 2. Create socket
    SOCKET serverSock = socket(AF_INET, SOCK_STREAM, 0);

    // 3. Bind to port 9000
    struct sockaddr_in server;
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = inet_addr("127.0.0.1");
    server.sin_port = htons(9000);
    bind(serverSock, (struct sockaddr*)&server, sizeof(server));

    // 4. Listen
    listen(serverSock, 1);
    printf("Waiting for AutoHotkey...\n");

    // 5. Accept connection
    SOCKET client = accept(serverSock, NULL, NULL);
    printf("Connected!\n");

    // 6. Receive init message
    char buffer[8192];
    // ... (receive code from above)

    // 7. Send run command
    const char* cmd = "run -i 1\0";
    send(client, cmd, strlen(cmd) + 1, 0);

    // 8. Receive response
    // ... (receive code from above)

    // 9. Cleanup
    closesocket(client);
    closesocket(serverSock);
    WSACleanup();

    return 0;
}
```

## Advanced Techniques

### Non-Blocking Sockets

```cpp
// Make socket non-blocking
u_long mode = 1;  // 1 = non-blocking, 0 = blocking
ioctlsocket(client, FIONBIO, &mode);

// Now recv() returns immediately
int result = recv(client, buffer, sizeof(buffer), 0);
if (result == SOCKET_ERROR && WSAGetLastError() == WSAEWOULDBLOCK) {
    // No data available yet - can do other work
}
```

### Timeout on Receive

```cpp
// Set 5 second receive timeout
int timeout = 5000;  // milliseconds
setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, (char*)&timeout, sizeof(timeout));

// Now recv() will timeout after 5 seconds
int result = recv(client, buffer, sizeof(buffer), 0);
if (result == SOCKET_ERROR && WSAGetLastError() == WSAETIMEDOUT) {
    printf("Timeout waiting for response\n");
}
```

### Keep-Alive

```cpp
// Enable TCP keep-alive
BOOL keepAlive = TRUE;
setsockopt(client, SOL_SOCKET, SO_KEEPALIVE, (char*)&keepAlive, sizeof(keepAlive));

// Set keep-alive parameters
tcp_keepalive ka;
ka.onoff = 1;
ka.keepalivetime = 5000;      // Start after 5 seconds idle
ka.keepaliveinterval = 1000;  // Probe every 1 second
DWORD dwBytes;
WSAIoctl(client, SIO_KEEPALIVE_VALS, &ka, sizeof(ka), NULL, 0, &dwBytes, NULL, NULL);
```

### Select() for Multiple Operations

```cpp
// Wait for socket to be readable or writable
fd_set readSet;
FD_ZERO(&readSet);
FD_SET(client, &readSet);

struct timeval timeout;
timeout.tv_sec = 5;
timeout.tv_usec = 0;

int result = select(0, &readSet, NULL, NULL, &timeout);
if (result > 0) {
    if (FD_ISSET(client, &readSet)) {
        // Socket is readable - can recv() without blocking
        recv(client, buffer, sizeof(buffer), 0);
    }
}
```

## Common DBGp Commands

| Command | Description | Example |
|---------|-------------|---------|
| `run` | Continue execution | `run -i 1\0` |
| `step_into` | Step into function | `step_into -i 2\0` |
| `step_over` | Step over function | `step_over -i 3\0` |
| `step_out` | Step out of function | `step_out -i 4\0` |
| `stop` | Stop debugging | `stop -i 5\0` |
| `detach` | Detach debugger | `detach -i 6\0` |
| `breakpoint_set` | Set breakpoint | `breakpoint_set -t line -n 10 -i 7\0` |
| `breakpoint_remove` | Remove breakpoint | `breakpoint_remove -d <id> -i 8\0` |
| `breakpoint_list` | List breakpoints | `breakpoint_list -i 9\0` |
| `stack_get` | Get call stack | `stack_get -i 10\0` |
| `context_get` | Get variables | `context_get -i 11\0` |
| `property_get` | Get specific variable | `property_get -n myVar -i 12\0` |
| `feature_get` | Get feature info | `feature_get -n max_depth -i 13\0` |
| `status` | Get current status | `status -i 14\0` |

## Response Status Values

AutoHotkey responses include a `status` attribute:

- `starting` - Session just initialized
- `break` - Stopped at breakpoint or after step
- `running` - Currently executing
- `stopping` - About to terminate
- `stopped` - Session ended

Example:
```xml
<response command="step_into" transaction_id="2"
          status="break" reason="ok"
          filename="file:///C:/script.ahk" lineno="5"/>
```

## Variable Inspection

Variables in `context_get` responses are Base64-encoded:

```xml
<property name="myVar" fullname="myVar" type="string">
    SGVsbG8gV29ybGQ=
</property>
```

Decode in C++:
```cpp
// Base64 decode table
const char* base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void Base64Decode(const char* input, char* output) {
    // Implementation in winapi_interactive_client.cpp
}
```

Result: `"Hello World"`

## Error Handling

```cpp
// Check for Winsock errors
int result = send(client, data, len, 0);
if (result == SOCKET_ERROR) {
    int error = WSAGetLastError();

    switch (error) {
        case WSAECONNRESET:
            printf("Connection reset by AutoHotkey\n");
            break;
        case WSAETIMEDOUT:
            printf("Operation timed out\n");
            break;
        case WSAEWOULDBLOCK:
            printf("Socket would block (non-blocking mode)\n");
            break;
        default:
            printf("Socket error: %d\n", error);
    }
}
```

## Performance Tips

1. **Reuse Sockets**: Don't create/destroy sockets for each command
2. **Buffer Size**: Use 8KB buffers for most responses (stack traces can be large)
3. **Disable Nagle**: For low-latency debugging
   ```cpp
   BOOL noDelay = TRUE;
   setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char*)&noDelay, sizeof(noDelay));
   ```
4. **Use Non-Blocking**: For responsive UIs
5. **SO_REUSEADDR**: Prevents "Address already in use" errors during development
   ```cpp
   int opt = 1;
   setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt));
   ```

## Alternative: Named Pipes

For even better performance on Windows, use named pipes instead of sockets:

```cpp
// Server side (your debugger)
HANDLE hPipe = CreateNamedPipe(
    "\\\\.\\pipe\\AhkDebugger",
    PIPE_ACCESS_DUPLEX,
    PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
    1, 8192, 8192, 0, NULL
);

ConnectNamedPipe(hPipe, NULL);  // Wait for AutoHotkey

// Send command
DWORD written;
WriteFile(hPipe, "run -i 1\0", 10, &written, NULL);

// Receive response
DWORD read;
char buffer[8192];
ReadFile(hPipe, buffer, sizeof(buffer), &read, NULL);
```

**Note:** Requires modifying AutoHotkey's `Debugger.cpp` to support named pipes instead of sockets.

## Resources

- **Winsock Reference**: https://docs.microsoft.com/en-us/windows/win32/winsock/
- **DBGp Protocol Spec**: https://xdebug.org/docs/dbgp
- **AutoHotkey Source**: `source/Debugger.cpp` (3,255 lines)

## See Also

- `examples/winapi_simple_client.cpp` - Complete working example
- `examples/winapi_interactive_client.cpp` - Interactive debugger
- `IMPLEMENTATION_GUIDE.md` - Advanced debugging techniques
- `QUICK_START_GUIDE.md` - Beginner tutorials
