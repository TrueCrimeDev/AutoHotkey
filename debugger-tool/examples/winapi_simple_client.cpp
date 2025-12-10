/*
 * Simple WinAPI Debugger Client for AutoHotkey v2
 *
 * Compile with:
 *   MSVC:  cl winapi_simple_client.cpp /link ws2_32.lib
 *   MinGW: g++ winapi_simple_client.cpp -lws2_32 -o winapi_simple_client.exe
 *
 * Usage:
 *   1. Run this program first
 *   2. Run: AutoHotkey.exe /Debug your_script.ahk
 *   3. Watch the debugger control the script
 */

#include <winsock2.h>
#include <windows.h>
#include <stdio.h>

#pragma comment(lib, "ws2_32.lib")

// Function to receive a null-terminated message from the socket
BOOL ReceiveMessage(SOCKET sock, char* buffer, int bufferSize) {
    // First read the length prefix
    char lengthBuf[32] = {0};
    int lengthPos = 0;

    while (lengthPos < sizeof(lengthBuf) - 1) {
        if (recv(sock, &lengthBuf[lengthPos], 1, 0) <= 0) {
            printf("[!] Connection closed while reading length\n");
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

    // Read the actual message
    int received = 0;
    while (received < msgLength + 1) { // +1 for null terminator
        int result = recv(sock, buffer + received, msgLength + 1 - received, 0);
        if (result <= 0) {
            printf("[!] Connection closed while reading message\n");
            return FALSE;
        }
        received += result;
    }

    buffer[msgLength] = '\0'; // Ensure null termination
    return TRUE;
}

// Function to send a DBGp command
BOOL SendCommand(SOCKET sock, const char* command, int transactionId) {
    char buffer[256];
    int len = sprintf(buffer, "%s -i %d", command, transactionId);
    buffer[len] = '\0';
    len++; // Include null terminator

    if (send(sock, buffer, len, 0) == SOCKET_ERROR) {
        printf("[!] Send failed: %d\n", WSAGetLastError());
        return FALSE;
    }

    return TRUE;
}

int main() {
    WSADATA wsa;
    SOCKET serverSock, clientSock;
    struct sockaddr_in server;
    int transactionId = 1;
    char buffer[8192];

    printf("========================================\n");
    printf("  AutoHotkey v2 WinAPI Debugger Client\n");
    printf("========================================\n\n");

    // Initialize Winsock
    printf("[*] Initializing Winsock...\n");
    if (WSAStartup(MAKEWORD(2,2), &wsa) != 0) {
        printf("[!] WSAStartup failed: %d\n", WSAGetLastError());
        return 1;
    }

    // Create socket
    if ((serverSock = socket(AF_INET, SOCK_STREAM, 0)) == INVALID_SOCKET) {
        printf("[!] Socket creation failed: %d\n", WSAGetLastError());
        WSACleanup();
        return 1;
    }

    // Allow address reuse
    int opt = 1;
    setsockopt(serverSock, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt));

    // Setup server address
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = inet_addr("127.0.0.1");
    server.sin_port = htons(9000);

    // Bind
    if (bind(serverSock, (struct sockaddr*)&server, sizeof(server)) == SOCKET_ERROR) {
        printf("[!] Bind failed: %d\n", WSAGetLastError());
        printf("[!] Make sure no other debugger is running on port 9000\n");
        closesocket(serverSock);
        WSACleanup();
        return 1;
    }

    // Listen
    listen(serverSock, 1);
    printf("[*] Listening on 127.0.0.1:9000\n");
    printf("[*] Waiting for AutoHotkey to connect...\n");
    printf("[>] Run: AutoHotkey.exe /Debug your_script.ahk\n\n");

    // Accept connection
    clientSock = accept(serverSock, NULL, NULL);
    if (clientSock == INVALID_SOCKET) {
        printf("[!] Accept failed: %d\n", WSAGetLastError());
        closesocket(serverSock);
        WSACleanup();
        return 1;
    }

    printf("[+] AutoHotkey connected!\n\n");

    // Receive init message
    if (!ReceiveMessage(clientSock, buffer, sizeof(buffer))) {
        closesocket(clientSock);
        closesocket(serverSock);
        WSACleanup();
        return 1;
    }

    printf("[+] Init message received:\n");
    printf("    %s\n\n", buffer);

    // Get feature list
    printf("[*] Getting debugger features...\n");
    SendCommand(clientSock, "feature_get -n supports_async", transactionId++);
    ReceiveMessage(clientSock, buffer, sizeof(buffer));
    printf("[+] %s\n", buffer);

    // Set a breakpoint at line 1
    printf("\n[*] Setting breakpoint at line 1...\n");
    SendCommand(clientSock, "breakpoint_set -t line -f file:///%SCRIPT% -n 1", transactionId++);
    ReceiveMessage(clientSock, buffer, sizeof(buffer));
    printf("[+] %s\n", buffer);

    // Start execution
    printf("\n[*] Starting script execution (run)...\n");
    SendCommand(clientSock, "run", transactionId++);
    ReceiveMessage(clientSock, buffer, sizeof(buffer));
    printf("[+] %s\n", buffer);

    // Step through a few lines
    printf("\n[*] Stepping through 3 lines...\n");
    for (int i = 0; i < 3; i++) {
        printf("\n--- Step %d ---\n", i + 1);
        SendCommand(clientSock, "step_into", transactionId++);
        ReceiveMessage(clientSock, buffer, sizeof(buffer));
        printf("[+] %s\n", buffer);

        // Get stack info
        SendCommand(clientSock, "stack_get", transactionId++);
        ReceiveMessage(clientSock, buffer, sizeof(buffer));
        printf("[+] Stack: %s\n", buffer);
    }

    // Continue to end
    printf("\n[*] Continuing to end...\n");
    SendCommand(clientSock, "run", transactionId++);
    ReceiveMessage(clientSock, buffer, sizeof(buffer));
    printf("[+] %s\n", buffer);

    printf("\n[*] Debugger session complete!\n");

    // Cleanup
    closesocket(clientSock);
    closesocket(serverSock);
    WSACleanup();

    return 0;
}
