@echo off
cd /d "%~dp0"
set PATH=C:\msys64\mingw64\bin;%PATH%
if exist build_mingw rmdir /s /q build_mingw
mkdir build_mingw
cd build_mingw
cmake -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release ..
if errorlevel 1 (
    echo CMake configure failed
    exit /b 1
)
mingw32-make -j%NUMBER_OF_PROCESSORS%
if errorlevel 1 (
    echo Build failed
    exit /b 1
)
echo.
echo Build complete! Output: bin\AutoHotkey64.exe
