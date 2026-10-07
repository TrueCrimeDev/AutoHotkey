@echo off
setlocal enableextensions
cd /d "%~dp0"

REM ===========================================================================
REM  Convenience build: mingw-w64 (GCC) through CMake, in place into bin\.
REM
REM    Build:                    cmd.exe /c build.bat        (or just build.bat)
REM    Force a clean configure:  cmd.exe /c build.bat clean
REM
REM  Requires MSYS2 (https://www.msys2.org) with the mingw-w64 toolchain:
REM    pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
REM
REM  CMake is the supported build route. BUILD.md documents it for MSVC x64,
REM  MSVC Win32 and mingw-w64 x64 with isolated output directories
REM  (out\msvc\x64, out\mingw\x64), and CI builds all three that way. This
REM  script is the mingw route with CMake's default AHK_OUTPUT_DIR, so it
REM  builds in build_gcc\ and overwrites the engines in bin\. Use the BUILD.md
REM  commands for a build that leaves bin\ alone. AutoHotkeyx.sln and
REM  build_local.bat remain available for the GUI executable only.
REM  Output: bin\AutoHotkey64Console.exe (console) and bin\AutoHotkey64.exe (GUI)
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
    echo ^(MSVC or an isolated build: see the CMake commands in BUILD.md^)
    exit /b 1
)

set "PATH=%MINGW_BIN%;%PATH%"

if /i "%~1"=="clean" if exist build_gcc rmdir /s /q build_gcc

REM Prefer Ninja; fall back to MinGW Makefiles when ninja isn't installed.
set "GEN=MinGW Makefiles"
where /q ninja.exe && set "GEN=Ninja"
echo Generator: %GEN%   Toolchain: %MINGW_BIN%

cmake -S . -B build_gcc -G "%GEN%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER=gcc.exe ^
    -DCMAKE_CXX_COMPILER=g++.exe ^
    -DCMAKE_RC_COMPILER=windres.exe
if errorlevel 1 (
    echo.
    echo CONFIGURE FAILED  ^(retry with: build.bat clean^)
    exit /b 1
)

cmake --build build_gcc --parallel
if errorlevel 1 (
    echo.
    echo BUILD FAILED
    exit /b 1
)

echo.
echo Build complete! Output: bin\AutoHotkey64Console.exe and bin\AutoHotkey64.exe
