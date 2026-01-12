@echo off
setlocal EnableDelayedExpansion

echo ========================================
echo AutoHotkey CMake + MinGW Build
echo ========================================
echo.

REM Add MinGW to PATH
set "PATH=C:\msys64\mingw64\bin;%PATH%"

cd /d "%~dp0"

REM Clean and create build directory
if exist build_mingw rmdir /s /q build_mingw
mkdir build_mingw
cd build_mingw

REM Configure with CMake using MinGW
echo.
echo Configuring with CMake + MinGW Makefiles...
cmake -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ ..
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
        echo Checking for output...
        dir *.exe 2>nul
    )
) else (
    echo.
    echo BUILD FAILED! Check errors above.
)

pause
