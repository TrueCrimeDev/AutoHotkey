@echo off
set PATH=C:\msys64\mingw64\bin;%PATH%
cd /d "%~dp0"
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 1
cmake --build . --config Release
if errorlevel 1 exit /b 1
echo Build SUCCESS
