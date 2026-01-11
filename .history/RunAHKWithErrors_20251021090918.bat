@echo off
REM ==================================================================================
REM RunAHKWithErrors.bat
REM ==================================================================================
REM Convenience batch file to run AHK scripts with error interception
REM
REM Usage:
REM   RunAHKWithErrors.bat MyScript.ahk
REM   RunAHKWithErrors.bat C:\Path\To\Script.ahk arg1 arg2
REM
REM Add this directory to your PATH to use from anywhere
REM ==================================================================================

set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
set "WRAPPER=%~dp0RunWithErrorHandler.ahk"

REM Check if AutoHotkey exists
if not exist "%AHK_EXE%" (
    echo ERROR: AutoHotkey not found at: %AHK_EXE%
    echo Please update AHK_EXE in this batch file
    pause
    exit /b 1
)

REM Check if wrapper exists
if not exist "%WRAPPER%" (
    echo ERROR: Wrapper not found at: %WRAPPER%
    echo Please ensure RunWithErrorHandler.ahk is in the same directory
    pause
    exit /b 1
)

REM Check if script specified
if "%~1"=="" (
    echo Usage: %~nx0 ^<script.ahk^> [args...]
    pause
    exit /b 1
)

REM Run the script with error handler
"%AHK_EXE%" "%WRAPPER%" %*

exit /b %errorlevel%
