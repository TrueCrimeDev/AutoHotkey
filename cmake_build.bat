@echo off
setlocal

echo ========================================
echo AutoHotkey CMake Build
echo ========================================
echo.

cd /d "%~dp0"

REM Create build directory
if not exist build mkdir build
cd build

REM Configure with CMake
echo Configuring with CMake...
cmake -G "Visual Studio 17 2022" -A x64 ..
if %ERRORLEVEL% NEQ 0 (
    echo CMake configuration failed!
    pause
    exit /b 1
)

echo.
echo Building Release...
cmake --build . --config Release --parallel

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo ========================================
    if exist "..\bin\AutoHotkey64.exe" (
        echo Output: %~dp0bin\AutoHotkey64.exe
        dir "..\bin\AutoHotkey64.exe"
    )
) else (
    echo.
    echo BUILD FAILED!
)

pause
