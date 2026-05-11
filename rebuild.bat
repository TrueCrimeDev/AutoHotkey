@echo off
cd /d "%~dp0"
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /m /t:Rebuild
if errorlevel 1 (
    echo.
    echo REBUILD FAILED
    exit /b 1
)
echo.
echo Rebuild complete! Output: bin\AutoHotkey64.exe
