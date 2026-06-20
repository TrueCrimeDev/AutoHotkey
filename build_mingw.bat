@echo off
setlocal enableextensions
cd /d "%~dp0"

REM ===========================================================================
REM  mingw-w64 (GCC) build route for the AutoHotkey v2 Console fork.
REM
REM    Cross-compile from WSL:   cmd.exe /c build_mingw.bat
REM    Force a clean configure:  cmd.exe /c build_mingw.bat clean
REM
REM  Requires MSYS2 (https://www.msys2.org) with the mingw-w64 toolchain:
REM    pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
REM
REM  MSVC (build_local.bat) stays the canonical / distribution build. This path
REM  yields a larger, statically linked binary that is handy for dev work and is
REM  verified by the `build-mingw` CI job. Output: bin\AutoHotkey64.exe
REM ===========================================================================

REM MSYS2 install root (override with:  set MSYS2_ROOT=D:\msys64)
if not defined MSYS2_ROOT set "MSYS2_ROOT=C:\msys64"
set "MINGW_BIN=%MSYS2_ROOT%\mingw64\bin"

if not exist "%MINGW_BIN%\g++.exe" (
    echo.
    echo ERROR: mingw-w64 g++ not found at "%MINGW_BIN%".
    echo Install MSYS2 from https://www.msys2.org, then in the MSYS2 shell run:
    echo     pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
    echo Or point MSYS2_ROOT at your install:  set MSYS2_ROOT=D:\msys64
    exit /b 1
)

set "PATH=%MINGW_BIN%;%PATH%"

if /i "%~1"=="clean" if exist build_mingw rmdir /s /q build_mingw

REM Prefer Ninja; fall back to MinGW Makefiles when ninja isn't installed.
set "GEN=MinGW Makefiles"
where /q ninja.exe && set "GEN=Ninja"
echo Generator: %GEN%   Toolchain: %MINGW_BIN%

cmake -S . -B build_mingw -G "%GEN%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER=gcc.exe ^
    -DCMAKE_CXX_COMPILER=g++.exe ^
    -DCMAKE_RC_COMPILER=windres.exe
if errorlevel 1 (
    echo.
    echo CONFIGURE FAILED  ^(retry with: build_mingw.bat clean^)
    exit /b 1
)

cmake --build build_mingw --parallel
if errorlevel 1 (
    echo.
    echo BUILD FAILED
    exit /b 1
)

echo.
echo mingw build complete! Output: bin\AutoHotkey64.exe
