@echo off
set PATH=C:\msys64\mingw64\bin;%PATH%
cd /d "%~dp0"

REM Clean all object files for full rebuild
if exist CMakeFiles\AutoHotkey64.dir\source (
    del /Q CMakeFiles\AutoHotkey64.dir\source\*.obj 2>/dev/null
    del /Q CMakeFiles\AutoHotkey64.dir\source\*.obj.d 2>/dev/null
)

REM Reconfigure and rebuild
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 (
    echo CMake configure FAILED
    exit /b 1
)
cmake --build . --config Release -- -j%NUMBER_OF_PROCESSORS%
if errorlevel 1 (
    echo Build FAILED
    exit /b 1
)
echo Build SUCCESS
