@echo off
set "ahkExe=C:\Users\uphol\Documents\Design\Coding\AutoHotkey\bin\AutoHotkey64.exe"
set "script=C:\Users\uphol\Documents\Autohotkey\_.ahk"

REM Kill any running instances of this script
for /f "tokens=2" %%a in ('wmic process where "Name='AutoHotkey64.exe' and CommandLine like '%%_.ahk%%'" get ProcessId /value 2^>nul ^| find "="') do (
    echo Killing PID: %%a
    taskkill /PID %%a /F >nul 2>&1
)

timeout /t 1 /nobreak >nul

echo Starting: _.ahk
start "" "%ahkExe%" "%script%"
echo Done.
