@echo off
REM Build script for Microsoft Visual C++ (MSVC)
REM Requires Visual Studio or Build Tools installed

echo Building AutoHotkey WinAPI Debugger Clients...
echo.

echo [1/5] Building simple client...
cl /nologo /W3 /O2 winapi_simple_client.cpp /link ws2_32.lib
if %ERRORLEVEL% NEQ 0 (
    echo [!] Simple client build failed!
    exit /b 1
)
echo [+] winapi_simple_client.exe created

echo.
echo [2/5] Building interactive client...
cl /nologo /W3 /O2 winapi_interactive_client.cpp /link ws2_32.lib
if %ERRORLEVEL% NEQ 0 (
    echo [!] Interactive client build failed!
    exit /b 1
)
echo [+] winapi_interactive_client.exe created

echo.
echo [3/5] Building Windows Debug API client...
cl /nologo /W3 /O2 winapi_debug_api.cpp
if %ERRORLEVEL% NEQ 0 (
    echo [!] Debug API client build failed!
    exit /b 1
)
echo [+] winapi_debug_api.exe created

echo.
echo [4/5] Building shared memory reader...
cl /nologo /W3 /O2 winapi_shared_memory_reader.cpp
if %ERRORLEVEL% NEQ 0 (
    echo [!] Shared memory reader build failed!
    exit /b 1
)
echo [+] winapi_shared_memory_reader.exe created

echo.
echo [5/5] Building memory reader...
cl /nologo /W3 /O2 winapi_memory_reader.cpp /link psapi.lib
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

REM Clean up intermediate files
del *.obj 2>nul
