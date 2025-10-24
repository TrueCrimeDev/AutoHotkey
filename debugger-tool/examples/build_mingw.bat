@echo off
REM Build script for MinGW/GCC
REM Requires MinGW-w64 or similar GCC compiler for Windows

echo Building AutoHotkey WinAPI Debugger Clients with MinGW...
echo.

echo [1/2] Building simple client...
g++ -Wall -O2 winapi_simple_client.cpp -lws2_32 -o winapi_simple_client.exe
if %ERRORLEVEL% NEQ 0 (
    echo [!] Simple client build failed!
    echo [!] Make sure g++ is in your PATH
    exit /b 1
)
echo [+] winapi_simple_client.exe created

echo.
echo [2/2] Building interactive client...
g++ -Wall -O2 winapi_interactive_client.cpp -lws2_32 -o winapi_interactive_client.exe
if %ERRORLEVEL% NEQ 0 (
    echo [!] Interactive client build failed!
    exit /b 1
)
echo [+] winapi_interactive_client.exe created

echo.
echo ======================================
echo Build complete!
echo ======================================
echo.
echo Run: winapi_simple_client.exe
echo  or: winapi_interactive_client.exe
echo.
echo Then run: AutoHotkey.exe /Debug your_script.ahk
echo.
