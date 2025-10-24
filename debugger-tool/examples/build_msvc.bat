@echo off
REM Build script for Microsoft Visual C++ (MSVC)
REM Requires Visual Studio or Build Tools installed

echo Building AutoHotkey WinAPI Debugger Clients...
echo.

echo [1/2] Building simple client...
cl /nologo /W3 /O2 winapi_simple_client.cpp /link ws2_32.lib
if %ERRORLEVEL% NEQ 0 (
    echo [!] Simple client build failed!
    exit /b 1
)
echo [+] winapi_simple_client.exe created

echo.
echo [2/2] Building interactive client...
cl /nologo /W3 /O2 winapi_interactive_client.cpp /link ws2_32.lib
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

REM Clean up intermediate files
del *.obj 2>nul
