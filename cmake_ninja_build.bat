@echo off
setlocal EnableDelayedExpansion

echo ========================================
echo AutoHotkey CMake + Ninja Build
echo ========================================
echo.

REM Initialize VS environment using VsDevCmd
set "VSCMD_START_DIR=%~dp0"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64
) else (
    echo Visual Studio 2022 not found!
    pause
    exit /b 1
)

cd /d "%~dp0"

REM Clean and create build directory
if exist build_ninja rmdir /s /q build_ninja
mkdir build_ninja
cd build_ninja

REM Configure with CMake using Ninja
echo.
echo Configuring with CMake + Ninja...
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..
if !ERRORLEVEL! NEQ 0 (
    echo CMake configuration failed!
    pause
    exit /b 1
)

echo.
echo Building...
cmake --build . --parallel

if !ERRORLEVEL! EQU 0 (
    echo.
    echo ========================================
    echo BUILD SUCCESSFUL!
    echo ========================================
    if exist "..\bin\AutoHotkey64.exe" (
        echo Output: %~dp0bin\AutoHotkey64.exe
        dir "..\bin\AutoHotkey64.exe"
    ) else (
        echo Checking for output in current dir...
        dir *.exe 2>nul
    )
) else (
    echo.
    echo BUILD FAILED! Check errors above.
)

pause
