@echo off
REM Build AutoHotkey x64 Release with _ScriptGetLines
REM Run this from Windows (double-click or run from cmd)

echo Building AutoHotkey x64 Release...
echo.

REM Initialize VS2022 environment
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64

REM Navigate to project directory
cd /d "%~dp0"

REM Build
msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /t:Build /m

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo Output: %~dp0bin\AutoHotkey64.exe
    echo ========================================
    echo.
    dir bin\AutoHotkey64.exe
) else (
    echo.
    echo BUILD FAILED! Error code: %ERRORLEVEL%
)

pause
