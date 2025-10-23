@echo off
REM Generic launcher - drag any .ahk file onto this to debug it

if "%~1"=="" (
    echo Usage: Drag an AHK script onto this file to run with debugging
    echo Or run: RUN_WITH_DEBUG.bat YourScript.ahk
    pause
    exit /b
)

"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "%~dp0AutoDebug.ahk" "%~1"
