/*
 * Windows Debug API Example - Attach to AutoHotkey as Native Debugger
 *
 * This uses the ACTUAL Windows debugging API that Visual Studio uses!
 * No DBGp protocol needed - direct OS-level debugging.
 *
 * Compile with:
 *   MSVC:  cl winapi_debug_api.cpp /link advapi32.lib
 *   MinGW: g++ winapi_debug_api.cpp -o winapi_debug_api.exe
 *
 * Usage:
 *   1. Start AutoHotkey normally (no /Debug flag needed!)
 *   2. Run: winapi_debug_api.exe <PID>
 *   3. This attaches as a native debugger
 *
 * Capabilities:
 *   - Intercept ALL exceptions (breakpoints, errors)
 *   - Read/write process memory
 *   - Inspect thread states
 *   - Control execution (continue, single-step)
 *   - No modification to AutoHotkey needed!
 */

#include <windows.h>
#include <stdio.h>
#include <tlhelp32.h>

// Helper to get thread context
void PrintThreadContext(HANDLE hThread) {
    CONTEXT ctx;
    ctx.ContextFlags = CONTEXT_ALL;

    if (GetThreadContext(hThread, &ctx)) {
        printf("    Thread Context:\n");
        #ifdef _M_X64
        printf("      RIP (instruction pointer): 0x%llx\n", ctx.Rip);
        printf("      RSP (stack pointer):       0x%llx\n", ctx.Rsp);
        printf("      RBP (base pointer):        0x%llx\n", ctx.Rbp);
        #else
        printf("      EIP (instruction pointer): 0x%08x\n", ctx.Eip);
        printf("      ESP (stack pointer):       0x%08x\n", ctx.Esp);
        printf("      EBP (base pointer):        0x%08x\n", ctx.Ebp);
        #endif
    }
}

// Read memory from target process
BOOL ReadTargetMemory(HANDLE hProcess, LPVOID address, BYTE* buffer, SIZE_T size) {
    SIZE_T bytesRead;
    if (ReadProcessMemory(hProcess, address, buffer, size, &bytesRead)) {
        printf("[+] Read %zu bytes from 0x%p\n", bytesRead, address);
        return TRUE;
    }
    printf("[!] Failed to read memory at 0x%p: %d\n", address, GetLastError());
    return FALSE;
}

// Find AutoHotkey process by name
DWORD FindProcessByName(const char* processName) {
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32 pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32);

    if (Process32First(hSnapshot, &pe32)) {
        do {
            if (_stricmp(pe32.szExeFile, processName) == 0) {
                CloseHandle(hSnapshot);
                return pe32.th32ProcessID;
            }
        } while (Process32Next(hSnapshot, &pe32));
    }

    CloseHandle(hSnapshot);
    return 0;
}

int main(int argc, char* argv[]) {
    DWORD pid;

    printf("=========================================\n");
    printf("  Windows Debug API - AutoHotkey Debugger\n");
    printf("=========================================\n\n");

    // Get PID
    if (argc < 2) {
        printf("[*] No PID specified, searching for AutoHotkey.exe...\n");
        pid = FindProcessByName("AutoHotkey.exe");
        if (pid == 0) {
            printf("[!] AutoHotkey.exe not found!\n");
            printf("[>] Usage: %s <PID>\n", argv[0]);
            printf("[>]    or: Start AutoHotkey.exe first\n");
            return 1;
        }
        printf("[+] Found AutoHotkey.exe with PID: %d\n\n", pid);
    } else {
        pid = atoi(argv[1]);
    }

    // Attach as debugger
    printf("[*] Attaching to process %d...\n", pid);
    if (!DebugActiveProcess(pid)) {
        printf("[!] Failed to attach: %d\n", GetLastError());
        printf("[!] Make sure:\n");
        printf("    - You have admin privileges\n");
        printf("    - Process exists\n");
        printf("    - No other debugger is attached\n");
        return 1;
    }

    printf("[+] Successfully attached as debugger!\n");
    printf("[*] AutoHotkey is now paused. Waiting for debug events...\n\n");

    // Debug event loop
    DEBUG_EVENT debugEvent;
    BOOL continueDebugging = TRUE;
    int eventCount = 0;

    while (continueDebugging && WaitForDebugEvent(&debugEvent, INFINITE)) {
        DWORD continueStatus = DBG_CONTINUE;
        eventCount++;

        printf("\n=== Event #%d ===\n", eventCount);
        printf("Process ID: %d, Thread ID: %d\n",
               debugEvent.dwProcessId, debugEvent.dwThreadId);

        switch (debugEvent.dwDebugEventCode) {
            case EXCEPTION_DEBUG_EVENT: {
                EXCEPTION_DEBUG_INFO& exc = debugEvent.u.Exception;
                printf("Event: EXCEPTION\n");
                printf("  Exception Code: 0x%08x\n", exc.ExceptionRecord.ExceptionCode);
                printf("  Address: 0x%p\n", exc.ExceptionRecord.ExceptionAddress);
                printf("  First Chance: %s\n", exc.dwFirstChance ? "Yes" : "No");

                // Decode common exceptions
                switch (exc.ExceptionRecord.ExceptionCode) {
                    case EXCEPTION_BREAKPOINT:
                        printf("  Type: Breakpoint\n");
                        if (!exc.dwFirstChance) {
                            printf("  [!] Unhandled breakpoint - this is unusual\n");
                        }
                        break;
                    case EXCEPTION_SINGLE_STEP:
                        printf("  Type: Single Step\n");
                        break;
                    case EXCEPTION_ACCESS_VIOLATION:
                        printf("  Type: Access Violation\n");
                        printf("  [!] Memory error at 0x%p\n",
                               (void*)exc.ExceptionRecord.ExceptionInformation[1]);
                        break;
                    case EXCEPTION_ILLEGAL_INSTRUCTION:
                        printf("  Type: Illegal Instruction\n");
                        break;
                    case EXCEPTION_INT_DIVIDE_BY_ZERO:
                        printf("  Type: Divide by Zero\n");
                        break;
                    case EXCEPTION_STACK_OVERFLOW:
                        printf("  Type: Stack Overflow\n");
                        break;
                }

                // Get thread context for exceptions
                HANDLE hThread = OpenThread(THREAD_ALL_ACCESS, FALSE, debugEvent.dwThreadId);
                if (hThread) {
                    PrintThreadContext(hThread);
                    CloseHandle(hThread);
                }

                // Only handle first-chance breakpoints automatically
                if (exc.ExceptionRecord.ExceptionCode == EXCEPTION_BREAKPOINT &&
                    exc.dwFirstChance) {
                    continueStatus = DBG_CONTINUE;
                } else {
                    continueStatus = DBG_EXCEPTION_NOT_HANDLED;
                }
                break;
            }

            case CREATE_THREAD_DEBUG_EVENT:
                printf("Event: CREATE_THREAD\n");
                printf("  Thread Handle: 0x%p\n", debugEvent.u.CreateThread.hThread);
                printf("  Start Address: 0x%p\n", debugEvent.u.CreateThread.lpStartAddress);
                break;

            case CREATE_PROCESS_DEBUG_EVENT: {
                CREATE_PROCESS_DEBUG_INFO& cp = debugEvent.u.CreateProcessInfo;
                printf("Event: CREATE_PROCESS\n");
                printf("  Process Handle: 0x%p\n", cp.hProcess);
                printf("  Thread Handle: 0x%p\n", cp.hThread);
                printf("  Base Address: 0x%p\n", cp.lpBaseOfImage);
                printf("  Entry Point: 0x%p\n", cp.lpStartAddress);

                // We can read memory now!
                BYTE buffer[16];
                if (ReadTargetMemory(cp.hProcess, cp.lpBaseOfImage, buffer, 16)) {
                    printf("  First 16 bytes at base:\n    ");
                    for (int i = 0; i < 16; i++) {
                        printf("%02x ", buffer[i]);
                    }
                    printf("\n");
                }
                break;
            }

            case EXIT_THREAD_DEBUG_EVENT:
                printf("Event: EXIT_THREAD\n");
                printf("  Exit Code: %d\n", debugEvent.u.ExitThread.dwExitCode);
                break;

            case EXIT_PROCESS_DEBUG_EVENT:
                printf("Event: EXIT_PROCESS\n");
                printf("  Exit Code: %d\n", debugEvent.u.ExitProcess.dwExitCode);
                printf("\n[*] Target process exited. Stopping debugger.\n");
                continueDebugging = FALSE;
                break;

            case LOAD_DLL_DEBUG_EVENT: {
                LOAD_DLL_DEBUG_INFO& dll = debugEvent.u.LoadDll;
                printf("Event: LOAD_DLL\n");
                printf("  Base Address: 0x%p\n", dll.lpBaseOfDll);

                // Try to read DLL name (it's in the target process memory)
                if (dll.lpImageName && dll.fUnicode) {
                    HANDLE hProcess = OpenProcess(PROCESS_VM_READ, FALSE, debugEvent.dwProcessId);
                    if (hProcess) {
                        LPVOID namePtr;
                        SIZE_T bytesRead;
                        if (ReadProcessMemory(hProcess, dll.lpImageName, &namePtr,
                                            sizeof(namePtr), &bytesRead) && namePtr) {
                            WCHAR dllName[MAX_PATH];
                            if (ReadProcessMemory(hProcess, namePtr, dllName,
                                                sizeof(dllName), &bytesRead)) {
                                wprintf(L"  DLL Name: %s\n", dllName);
                            }
                        }
                        CloseHandle(hProcess);
                    }
                }
                CloseHandle(dll.hFile);
                break;
            }

            case UNLOAD_DLL_DEBUG_EVENT:
                printf("Event: UNLOAD_DLL\n");
                printf("  Base Address: 0x%p\n", debugEvent.u.UnloadDll.lpBaseOfDll);
                break;

            case OUTPUT_DEBUG_STRING_EVENT: {
                OUTPUT_DEBUG_STRING_INFO& dbgStr = debugEvent.u.DebugString;
                printf("Event: OUTPUT_DEBUG_STRING\n");
                printf("  Length: %d bytes\n", dbgStr.nDebugStringLength);

                // Read the debug string from target process memory
                HANDLE hProcess = OpenProcess(PROCESS_VM_READ, FALSE, debugEvent.dwProcessId);
                if (hProcess) {
                    if (dbgStr.fUnicode) {
                        WCHAR* buffer = (WCHAR*)malloc(dbgStr.nDebugStringLength * sizeof(WCHAR));
                        SIZE_T bytesRead;
                        if (ReadProcessMemory(hProcess, dbgStr.lpDebugStringData,
                                            buffer, dbgStr.nDebugStringLength * sizeof(WCHAR),
                                            &bytesRead)) {
                            wprintf(L"  Message: %s\n", buffer);
                        }
                        free(buffer);
                    } else {
                        char* buffer = (char*)malloc(dbgStr.nDebugStringLength);
                        SIZE_T bytesRead;
                        if (ReadProcessMemory(hProcess, dbgStr.lpDebugStringData,
                                            buffer, dbgStr.nDebugStringLength, &bytesRead)) {
                            printf("  Message: %s\n", buffer);
                        }
                        free(buffer);
                    }
                    CloseHandle(hProcess);
                }
                break;
            }

            case RIP_EVENT:
                printf("Event: RIP (System debugging error)\n");
                printf("  Error: %d\n", debugEvent.u.RipInfo.dwError);
                printf("  Type: %d\n", debugEvent.u.RipInfo.dwType);
                break;
        }

        // Interactive control (limit to first 20 events for demo)
        if (eventCount >= 20) {
            printf("\n[*] Reached 20 events. Press 'q' to quit, any other key to continue: ");
            char c = getchar();
            if (c == 'q' || c == 'Q') {
                printf("[*] Detaching from process...\n");
                DebugActiveProcessStop(pid);
                continueDebugging = FALSE;
            }
            eventCount = 0;
        }

        // Continue execution
        if (continueDebugging) {
            ContinueDebugEvent(debugEvent.dwProcessId,
                             debugEvent.dwThreadId,
                             continueStatus);
        }
    }

    printf("\n[*] Debugger session ended.\n");
    return 0;
}
