/*
 * Interactive WinAPI Debugger Client for AutoHotkey v2
 *
 * Compile with:
 *   MSVC:  cl winapi_interactive_client.cpp /link ws2_32.lib
 *   MinGW: g++ winapi_interactive_client.cpp -lws2_32 -o winapi_interactive_client.exe
 *
 * Usage:
 *   1. Run this program first
 *   2. Run: AutoHotkey.exe /Debug your_script.ahk
 *   3. Type commands interactively
 *
 * Commands:
 *   run, step, next, finish, quit
 *   stack, context, breakpoint <file> <line>
 */

#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

#pragma comment(lib, "ws2_32.lib")

SOCKET g_clientSock = INVALID_SOCKET;
int g_transactionId = 1;

// Base64 decode (simplified - handles basic cases)
void Base64Decode(const char* input, char* output, int outputSize) {
    static const char base64_table[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    int len = strlen(input);
    int i = 0, j = 0;
    unsigned char buffer[4];

    for (int k = 0; k < len && j < outputSize - 1; ) {
        // Get 4 base64 chars
        int count = 0;
        for (int n = 0; n < 4 && k < len; n++, k++) {
            if (input[k] == '=') {
                buffer[n] = 0;
            } else {
                const char* p = strchr(base64_table, input[k]);
                buffer[n] = p ? (p - base64_table) : 0;
            }
            count++;
        }

        // Decode to 3 bytes
        if (count >= 2) output[j++] = (buffer[0] << 2) | (buffer[1] >> 4);
        if (count >= 3) output[j++] = (buffer[1] << 4) | (buffer[2] >> 2);
        if (count >= 4) output[j++] = (buffer[2] << 6) | buffer[3];
    }
    output[j] = '\0';
}

// Extract value from XML property element
void ExtractValue(const char* xml, char* output, int outputSize) {
    const char* start = strstr(xml, ">");
    if (!start) {
        output[0] = '\0';
        return;
    }
    start++; // Skip '>'

    const char* end = strstr(start, "</");
    if (!end) {
        output[0] = '\0';
        return;
    }

    int len = end - start;
    if (len >= outputSize) len = outputSize - 1;

    strncpy(output, start, len);
    output[len] = '\0';
}

BOOL ReceiveMessage(SOCKET sock, char* buffer, int bufferSize) {
    char lengthBuf[32] = {0};
    int lengthPos = 0;

    while (lengthPos < sizeof(lengthBuf) - 1) {
        if (recv(sock, &lengthBuf[lengthPos], 1, 0) <= 0) {
            return FALSE;
        }
        if (lengthBuf[lengthPos] == '\0') break;
        lengthPos++;
    }

    int msgLength = atoi(lengthBuf);
    if (msgLength >= bufferSize) {
        printf("[!] Message too large: %d bytes\n", msgLength);
        return FALSE;
    }

    int received = 0;
    while (received < msgLength + 1) {
        int result = recv(sock, buffer + received, msgLength + 1 - received, 0);
        if (result <= 0) return FALSE;
        received += result;
    }

    buffer[msgLength] = '\0';
    return TRUE;
}

BOOL SendCommand(const char* command) {
    char buffer[512];
    int len = sprintf(buffer, "%s -i %d", command, g_transactionId++);
    buffer[len] = '\0';
    len++;

    if (send(g_clientSock, buffer, len, 0) == SOCKET_ERROR) {
        printf("[!] Send failed: %d\n", WSAGetLastError());
        return FALSE;
    }

    return TRUE;
}

void PrintHelp() {
    printf("\nAvailable Commands:\n");
    printf("  run         - Continue execution\n");
    printf("  step        - Step into (line by line, enter functions)\n");
    printf("  next        - Step over (line by line, skip functions)\n");
    printf("  finish      - Step out (run until function returns)\n");
    printf("  stack       - Show call stack\n");
    printf("  context     - Show current variables\n");
    printf("  break <n>   - Set breakpoint at line <n>\n");
    printf("  status      - Get execution status\n");
    printf("  help        - Show this help\n");
    printf("  quit        - Exit debugger\n\n");
}

void HandleCommand(const char* cmd) {
    char buffer[8192];
    char response[8192];

    if (strcmp(cmd, "run") == 0) {
        SendCommand("run");
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));
        printf("\n[Response] %s\n", buffer);

    } else if (strcmp(cmd, "step") == 0) {
        SendCommand("step_into");
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));

        // Extract current line from response
        const char* line = strstr(buffer, "lineno=\"");
        if (line) {
            line += 8; // Skip 'lineno="'
            int lineNo = atoi(line);
            printf("\n[Now at line %d]\n", lineNo);
        }

    } else if (strcmp(cmd, "next") == 0) {
        SendCommand("step_over");
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));

        const char* line = strstr(buffer, "lineno=\"");
        if (line) {
            line += 8;
            int lineNo = atoi(line);
            printf("\n[Now at line %d]\n", lineNo);
        }

    } else if (strcmp(cmd, "finish") == 0) {
        SendCommand("step_out");
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));
        printf("\n[Response] %s\n", buffer);

    } else if (strcmp(cmd, "stack") == 0) {
        SendCommand("stack_get");
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));

        printf("\n=== Call Stack ===\n");
        const char* ptr = buffer;
        int level = 0;
        while ((ptr = strstr(ptr, "<stack ")) != NULL) {
            const char* levelStr = strstr(ptr, "level=\"");
            const char* lineStr = strstr(ptr, "lineno=\"");
            const char* fileStr = strstr(ptr, "filename=\"");
            const char* funcStr = strstr(ptr, "where=\"");

            if (levelStr && lineStr) {
                levelStr += 7;
                lineStr += 8;

                int lvl = atoi(levelStr);
                int line = atoi(lineStr);

                char func[128] = "main";
                if (funcStr) {
                    funcStr += 7;
                    const char* funcEnd = strchr(funcStr, '"');
                    if (funcEnd) {
                        int len = funcEnd - funcStr;
                        if (len >= sizeof(func)) len = sizeof(func) - 1;
                        strncpy(func, funcStr, len);
                        func[len] = '\0';
                    }
                }

                printf("  #%d  %s() at line %d\n", lvl, func, line);
            }
            ptr++;
        }
        printf("\n");

    } else if (strcmp(cmd, "context") == 0) {
        SendCommand("context_get");
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));

        printf("\n=== Variables ===\n");
        const char* ptr = buffer;
        while ((ptr = strstr(ptr, "<property name=\"")) != NULL) {
            ptr += 16; // Skip '<property name="'

            const char* nameEnd = strchr(ptr, '"');
            if (!nameEnd) break;

            char name[128];
            int nameLen = nameEnd - ptr;
            if (nameLen >= sizeof(name)) nameLen = sizeof(name) - 1;
            strncpy(name, ptr, nameLen);
            name[nameLen] = '\0';

            // Find the value (base64 encoded)
            const char* valStart = strstr(nameEnd, ">");
            if (valStart) {
                valStart++; // Skip '>'
                const char* valEnd = strstr(valStart, "</property>");
                if (valEnd && valEnd > valStart) {
                    char encoded[512];
                    int encLen = valEnd - valStart;
                    if (encLen >= sizeof(encoded)) encLen = sizeof(encoded) - 1;
                    strncpy(encoded, valStart, encLen);
                    encoded[encLen] = '\0';

                    char decoded[512];
                    Base64Decode(encoded, decoded, sizeof(decoded));

                    printf("  %s = %s\n", name, decoded);
                }
            }

            ptr = nameEnd;
        }
        printf("\n");

    } else if (strncmp(cmd, "break ", 6) == 0) {
        int line = atoi(cmd + 6);
        char command[256];
        sprintf(command, "breakpoint_set -t line -n %d", line);
        SendCommand(command);
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));
        printf("\n[Breakpoint set at line %d]\n", line);

    } else if (strcmp(cmd, "status") == 0) {
        SendCommand("status");
        ReceiveMessage(g_clientSock, buffer, sizeof(buffer));
        printf("\n[Status] %s\n", buffer);

    } else if (strcmp(cmd, "help") == 0) {
        PrintHelp();

    } else {
        printf("\n[!] Unknown command: %s\n", cmd);
        printf("    Type 'help' for available commands\n");
    }
}

int main() {
    WSADATA wsa;
    SOCKET serverSock;
    struct sockaddr_in server;
    char buffer[8192];
    char command[256];

    printf("==========================================\n");
    printf("  AutoHotkey v2 Interactive WinAPI Client\n");
    printf("==========================================\n\n");

    if (WSAStartup(MAKEWORD(2,2), &wsa) != 0) {
        printf("[!] WSAStartup failed: %d\n", WSAGetLastError());
        return 1;
    }

    if ((serverSock = socket(AF_INET, SOCK_STREAM, 0)) == INVALID_SOCKET) {
        printf("[!] Socket creation failed: %d\n", WSAGetLastError());
        WSACleanup();
        return 1;
    }

    int opt = 1;
    setsockopt(serverSock, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt));

    server.sin_family = AF_INET;
    server.sin_addr.s_addr = inet_addr("127.0.0.1");
    server.sin_port = htons(9000);

    if (bind(serverSock, (struct sockaddr*)&server, sizeof(server)) == SOCKET_ERROR) {
        printf("[!] Bind failed: %d\n", WSAGetLastError());
        closesocket(serverSock);
        WSACleanup();
        return 1;
    }

    listen(serverSock, 1);
    printf("[*] Listening on 127.0.0.1:9000\n");
    printf("[*] Waiting for AutoHotkey...\n");
    printf("[>] Run: AutoHotkey.exe /Debug your_script.ahk\n\n");

    g_clientSock = accept(serverSock, NULL, NULL);
    if (g_clientSock == INVALID_SOCKET) {
        printf("[!] Accept failed: %d\n", WSAGetLastError());
        closesocket(serverSock);
        WSACleanup();
        return 1;
    }

    printf("[+] Connected!\n\n");

    // Receive init
    ReceiveMessage(g_clientSock, buffer, sizeof(buffer));
    printf("[Init] Connected to AutoHotkey debugger\n");

    PrintHelp();
    printf("Script is paused. Type 'run' to start or 'step' to step through.\n\n");

    // Interactive loop
    while (1) {
        printf("dbg> ");
        fflush(stdout);

        if (!fgets(command, sizeof(command), stdin)) break;

        // Remove newline
        command[strcspn(command, "\r\n")] = '\0';

        if (strlen(command) == 0) continue;
        if (strcmp(command, "quit") == 0) break;

        HandleCommand(command);
    }

    printf("\n[*] Closing connection...\n");
    closesocket(g_clientSock);
    closesocket(serverSock);
    WSACleanup();

    return 0;
}
