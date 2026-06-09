@echo off
REM Restart-runner: kills any prior instance of the target script, then relaunches it.
REM Usage: run_ahk.bat [path\to\script.ahk]   (defaults to _.ahk next to this file)
set "ahkExe=%~dp0..\bin\AutoHotkey64.exe"
set "script=%~1"
if "%script%"=="" set "script=%~dp0_.ahk"

REM Kill any running instances of this script
for /f "tokens=2" %%a in ('wmic process where "Name='AutoHotkey64.exe' and CommandLine like '%%_.ahk%%'" get ProcessId /value 2^>nul ^| find "="') do (
    echo Killing PID: %%a
    taskkill /PID %%a /F >nul 2>&1
)

timeout /t 1 /nobreak >nul

echo Starting: _.ahk
start "" "%ahkExe%" "%script%"
echo Done.
