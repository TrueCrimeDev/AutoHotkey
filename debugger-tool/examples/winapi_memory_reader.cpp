/*
 * Direct Memory Reader - Read AutoHotkey's Memory Without Debugging
 *
 * This uses ReadProcessMemory to inspect AutoHotkey's internal state
 * WITHOUT attaching as a debugger or using the DBGp protocol!
 *
 * Compile with:
 *   MSVC:  cl winapi_memory_reader.cpp
 *   MinGW: g++ winapi_memory_reader.cpp -o winapi_memory_reader.exe
 *
 * Usage:
 *   1. Run AutoHotkey (any script)
 *   2. Run: winapi_memory_reader.exe <PID>
 *   3. This reads AutoHotkey's memory to find debugging info
 *
 * Capabilities:
 *   - Read any memory address
 *   - Search for patterns (signatures)
 *   - Find global variables
 *   - Extract strings and data structures
 *   - No modification to AutoHotkey needed!
 *   - Works even without /Debug flag!
 */

#include <windows.h>
#include <psapi.h>
#include <stdio.h>
#include <tlhelp32.h>

#pragma comment(lib, "psapi.lib")

// Find process by name
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

// Read memory safely
BOOL ReadMemorySafe(HANDLE hProcess, LPCVOID address, LPVOID buffer, SIZE_T size) {
    SIZE_T bytesRead;
    if (ReadProcessMemory(hProcess, address, buffer, size, &bytesRead)) {
        return bytesRead == size;
    }
    return FALSE;
}

// Hex dump helper
void HexDump(const BYTE* data, SIZE_T size, SIZE_T bytesPerLine = 16) {
    for (SIZE_T i = 0; i < size; i += bytesPerLine) {
        printf("  %08zx: ", i);

        // Hex
        for (SIZE_T j = 0; j < bytesPerLine; j++) {
            if (i + j < size) {
                printf("%02x ", data[i + j]);
            } else {
                printf("   ");
            }
        }

        printf(" ");

        // ASCII
        for (SIZE_T j = 0; j < bytesPerLine && i + j < size; j++) {
            BYTE b = data[i + j];
            printf("%c", (b >= 32 && b < 127) ? b : '.');
        }
        printf("\n");
    }
}

// Search for a pattern in memory
LPVOID FindPattern(HANDLE hProcess, LPVOID start, SIZE_T searchSize,
                   const BYTE* pattern, SIZE_T patternSize) {
    const SIZE_T CHUNK_SIZE = 4096;
    BYTE buffer[CHUNK_SIZE];

    for (SIZE_T offset = 0; offset < searchSize; offset += CHUNK_SIZE - patternSize) {
        LPVOID searchAddr = (BYTE*)start + offset;
        SIZE_T readSize = min(CHUNK_SIZE, searchSize - offset);

        if (ReadMemorySafe(hProcess, searchAddr, buffer, readSize)) {
            for (SIZE_T i = 0; i <= readSize - patternSize; i++) {
                if (memcmp(buffer + i, pattern, patternSize) == 0) {
                    return (BYTE*)searchAddr + i;
                }
            }
        }
    }

    return NULL;
}

// Get module information
BOOL GetModuleInfo(HANDLE hProcess, const char* moduleName,
                   MODULEINFO* moduleInfo, HMODULE* hModule) {
    HMODULE hMods[1024];
    DWORD cbNeeded;

    if (EnumProcessModules(hProcess, hMods, sizeof(hMods), &cbNeeded)) {
        for (unsigned int i = 0; i < (cbNeeded / sizeof(HMODULE)); i++) {
            char szModName[MAX_PATH];

            if (GetModuleBaseName(hProcess, hMods[i], szModName, sizeof(szModName))) {
                if (_stricmp(szModName, moduleName) == 0) {
                    if (GetModuleInformation(hProcess, hMods[i], moduleInfo,
                                           sizeof(MODULEINFO))) {
                        if (hModule) *hModule = hMods[i];
                        return TRUE;
                    }
                }
            }
        }
    }
    return FALSE;
}

// Read a null-terminated string from memory
BOOL ReadString(HANDLE hProcess, LPCVOID address, char* buffer, SIZE_T maxLen) {
    for (SIZE_T i = 0; i < maxLen - 1; i++) {
        if (!ReadMemorySafe(hProcess, (BYTE*)address + i, &buffer[i], 1)) {
            buffer[i] = '\0';
            return i > 0;
        }
        if (buffer[i] == '\0') {
            return TRUE;
        }
    }
    buffer[maxLen - 1] = '\0';
    return TRUE;
}

int main(int argc, char* argv[]) {
    DWORD pid;

    printf("================================================\n");
    printf("  Direct Memory Reader for AutoHotkey\n");
    printf("================================================\n\n");

    // Get PID
    if (argc < 2) {
        printf("[*] No PID specified, searching for AutoHotkey.exe...\n");
        pid = FindProcessByName("AutoHotkey.exe");
        if (pid == 0) {
            printf("[!] AutoHotkey.exe not found!\n");
            printf("[>] Usage: %s <PID>\n", argv[0]);
            return 1;
        }
        printf("[+] Found AutoHotkey.exe with PID: %d\n\n", pid);
    } else {
        pid = atoi(argv[1]);
    }

    // Open process
    printf("[*] Opening process %d...\n", pid);
    HANDLE hProcess = OpenProcess(
        PROCESS_VM_READ | PROCESS_QUERY_INFORMATION,
        FALSE,
        pid
    );

    if (hProcess == NULL) {
        printf("[!] Failed to open process: %d\n", GetLastError());
        printf("[!] Make sure:\n");
        printf("    - Process exists\n");
        printf("    - You have appropriate privileges\n");
        return 1;
    }

    printf("[+] Process opened successfully!\n\n");

    // Get AutoHotkey.exe module info
    MODULEINFO moduleInfo;
    HMODULE hModule;
    if (!GetModuleInfo(hProcess, "AutoHotkey.exe", &moduleInfo, &hModule)) {
        printf("[!] Could not get module information\n");
        CloseHandle(hProcess);
        return 1;
    }

    printf("[+] AutoHotkey.exe module found:\n");
    printf("    Base Address: 0x%p\n", moduleInfo.lpBaseOfDll);
    printf("    Size:         %u bytes (%.2f MB)\n",
           moduleInfo.SizeOfImage,
           moduleInfo.SizeOfImage / (1024.0 * 1024.0));
    printf("    Entry Point:  0x%p\n\n", moduleInfo.EntryPoint);

    // Read PE header
    printf("[*] Reading PE header...\n");
    IMAGE_DOS_HEADER dosHeader;
    if (ReadMemorySafe(hProcess, moduleInfo.lpBaseOfDll, &dosHeader, sizeof(dosHeader))) {
        if (dosHeader.e_magic == IMAGE_DOS_SIGNATURE) {
            printf("[+] Valid PE executable (MZ signature found)\n");

            IMAGE_NT_HEADERS ntHeaders;
            LPVOID ntHeaderAddr = (BYTE*)moduleInfo.lpBaseOfDll + dosHeader.e_lfanew;
            if (ReadMemorySafe(hProcess, ntHeaderAddr, &ntHeaders, sizeof(ntHeaders))) {
                printf("    Machine: 0x%x (%s)\n",
                       ntHeaders.FileHeader.Machine,
                       ntHeaders.FileHeader.Machine == IMAGE_FILE_MACHINE_AMD64 ? "x64" :
                       ntHeaders.FileHeader.Machine == IMAGE_FILE_MACHINE_I386 ? "x86" : "Unknown");
                printf("    Timestamp: %u\n", ntHeaders.FileHeader.TimeDateStamp);
                printf("    Sections: %d\n", ntHeaders.FileHeader.NumberOfSections);
            }
        }
    }

    // Search for debugging-related strings
    printf("\n[*] Searching for debug-related patterns...\n");

    // Search for "DBGp" string (debugger protocol identifier)
    const char dbgpPattern[] = "DBGp";
    LPVOID dbgpAddr = FindPattern(hProcess,
                                  moduleInfo.lpBaseOfDll,
                                  moduleInfo.SizeOfImage,
                                  (const BYTE*)dbgpPattern,
                                  strlen(dbgpPattern));

    if (dbgpAddr) {
        printf("[+] Found 'DBGp' string at: 0x%p\n", dbgpAddr);

        // Read surrounding context
        BYTE context[128];
        if (ReadMemorySafe(hProcess, (BYTE*)dbgpAddr - 32, context, sizeof(context))) {
            printf("    Context (±32 bytes):\n");
            HexDump(context, sizeof(context));
        }
    } else {
        printf("[-] 'DBGp' string not found (debugger may not be active)\n");
    }

    // Search for XML patterns
    const char xmlPattern[] = "<?xml";
    LPVOID xmlAddr = FindPattern(hProcess,
                                 moduleInfo.lpBaseOfDll,
                                 moduleInfo.SizeOfImage,
                                 (const BYTE*)xmlPattern,
                                 strlen(xmlPattern));

    if (xmlAddr) {
        printf("[+] Found XML pattern at: 0x%p\n", xmlAddr);

        // Try to read the XML string
        char xmlBuffer[512];
        if (ReadString(hProcess, xmlAddr, xmlBuffer, sizeof(xmlBuffer))) {
            printf("    XML content (first 512 bytes):\n");
            printf("    %s\n", xmlBuffer);
        }
    }

    // Search for common AutoHotkey global variables
    printf("\n[*] Searching for AutoHotkey internals...\n");

    // Look for the .data section (contains global variables)
    printf("[+] Scanning .data section for interesting values...\n");

    // Pattern: Look for potential line numbers (small integers < 100000)
    // This is a heuristic - we're looking for what might be current line numbers
    SIZE_T scanSize = min(moduleInfo.SizeOfImage, 1024 * 1024); // Limit to 1MB
    BYTE* scanBuffer = (BYTE*)malloc(scanSize);

    if (scanBuffer && ReadMemorySafe(hProcess, moduleInfo.lpBaseOfDll, scanBuffer, scanSize)) {
        printf("[+] Scanning memory for potential runtime data...\n");

        // Look for small integers that might be line numbers (4-byte aligned)
        int foundCount = 0;
        for (SIZE_T i = 0; i < scanSize - 4 && foundCount < 10; i += 4) {
            DWORD value = *(DWORD*)(scanBuffer + i);

            // Heuristic: line numbers are typically 1-10000
            if (value > 0 && value < 10000) {
                // Check if this looks like it could be part of a structure
                // by seeing if there are other plausible values nearby
                DWORD prev = (i >= 4) ? *(DWORD*)(scanBuffer + i - 4) : 0;
                DWORD next = (i + 4 < scanSize) ? *(DWORD*)(scanBuffer + i + 4) : 0;

                // If surrounded by reasonable values, report it
                if ((prev == 0 || (prev > 0 && prev < 1000000)) &&
                    (next == 0 || (next > 0 && next < 1000000))) {
                    LPVOID addr = (BYTE*)moduleInfo.lpBaseOfDll + i;
                    printf("    Possible line number %u at offset 0x%zx (0x%p)\n",
                           value, i, addr);
                    foundCount++;
                }
            }
        }
    }
    free(scanBuffer);

    // Advanced: Try to find g_script global variable
    // This would require knowing the exact structure layout and is very fragile
    printf("\n[*] Advanced memory analysis:\n");
    printf("    Note: Finding specific global variables requires:\n");
    printf("    - Exact knowledge of AutoHotkey's build configuration\n");
    printf("    - Symbol file (.pdb) or reverse engineering\n");
    printf("    - Memory structure layout matching the running version\n");
    printf("\n    For reliable access, use one of these instead:\n");
    printf("    1. DBGp protocol (sockets) - examples/winapi_*_client.cpp\n");
    printf("    2. Windows Debug API - examples/winapi_debug_api.cpp\n");
    printf("    3. Shared memory - examples/winapi_shared_memory_reader.cpp\n");

    // Cleanup
    CloseHandle(hProcess);

    printf("\n[*] Memory scan complete!\n");
    return 0;
}

/*
 * === ADVANCED TECHNIQUES ===
 *
 * For more reliable memory reading, you can:
 *
 * 1. Load AutoHotkey's PDB symbols:
 *
 *    #include <dbghelp.h>
 *    #pragma comment(lib, "dbghelp.lib")
 *
 *    SymInitialize(hProcess, NULL, TRUE);
 *    SymLoadModuleEx(hProcess, NULL, "AutoHotkey.exe", NULL,
 *                    (DWORD64)moduleInfo.lpBaseOfDll, moduleInfo.SizeOfImage,
 *                    NULL, 0);
 *
 *    SYMBOL_INFO* symbol = (SYMBOL_INFO*)malloc(sizeof(SYMBOL_INFO) + 256);
 *    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
 *    symbol->MaxNameLen = 255;
 *
 *    if (SymFromName(hProcess, "g_script", symbol)) {
 *        printf("Found g_script at: 0x%llx\n", symbol->Address);
 *        // Now read the actual Script object
 *    }
 *
 * 2. Signature scanning (more reliable than string search):
 *
 *    Find unique byte patterns from disassembly:
 *    - Find function prologues (push ebp; mov ebp, esp; sub esp, XX)
 *    - Find constant comparisons (cmp eax, magic_number)
 *    - Find global variable accesses (mov eax, [g_script])
 *
 * 3. Use Process Hacker / x64dbg to find addresses manually first,
 *    then automate reading those addresses.
 *
 * 4. Hook functions with DLL injection:
 *    - Inject a DLL into AutoHotkey
 *    - Hook functions like Script::ExecLine
 *    - Read local variables directly from the stack
 *    - Most powerful but requires admin and kernel drivers
 */
