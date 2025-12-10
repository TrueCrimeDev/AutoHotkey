@echo off
REM Build script for MinGW/GCC
REM Requires MinGW-w64 or similar GCC compiler for Windows

echo Building AutoHotkey WinAPI Debugger Clients with MinGW...
echo.

echo [1/5] Building simple client...
g++ -Wall -O2 winapi_simple_client.cpp -lws2_32 -o winapi_simple_client.exe
if %ERRORLEVEL% NEQ 0 (
    echo [!] Simple client build failed!
    echo [!] Make sure g++ is in your PATH
    exit /b 1
)
echo [+] winapi_simple_client.exe created

echo.
echo [2/5] Building interactive client...
g++ -Wall -O2 winapi_interactive_client.cpp -lws2_32 -o winapi_interactive_client.exe
if %ERRORLEVEL% NEQ 0 (
    echo [!] Interactive client build failed!
    exit /b 1
)
echo [+] winapi_interactive_client.exe created

echo.
echo [3/5] Building Windows Debug API client...
g++ -Wall -O2 winapi_debug_api.cpp -o winapi_debug_api.exe
if %ERRORLEVEL% NEQ 0 (
    echo [!] Debug API client build failed!
    exit /b 1
)
echo [+] winapi_debug_api.exe created

echo.
echo [4/5] Building shared memory reader...
g++ -Wall -O2 winapi_shared_memory_reader.cpp -o winapi_shared_memory_reader.exe
if %ERRORLEVEL% NEQ 0 (
    echo [!] Shared memory reader build failed!
    exit /b 1
)
echo [+] winapi_shared_memory_reader.exe created

echo.
echo [5/5] Building memory reader...
g++ -Wall -O2 winapi_memory_reader.cpp -lpsapi -o winapi_memory_reader.exe
if %ERRORLEVEL% NEQ 0 (
    echo [!] Memory reader build failed!
    exit /b 1
)
echo [+] winapi_memory_reader.exe created

echo.
echo ======================================
echo Build complete!
echo ======================================
echo.
echo Standard DBGp clients:
echo   - winapi_simple_client.exe        (automated)
echo   - winapi_interactive_client.exe   (interactive)
echo.
echo Advanced WinAPI methods:
echo   - winapi_debug_api.exe            (Windows Debug API)
echo   - winapi_shared_memory_reader.exe (ultra-fast)
echo   - winapi_memory_reader.exe        (forensics)
echo.
echo See CUSTOM_WINAPI_DEBUGGING.md for usage details
echo.
