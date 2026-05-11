@echo off
cd /d "%~dp0"

REM VS 2026 BuildTools
if exist "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /m
    goto :checkresult
)

REM VS 2022 Community
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
    msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /m
    goto :checkresult
)

REM VS 2022 BuildTools
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
    msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /m
    goto :checkresult
)

REM VS 2019
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
    msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /m
    goto :checkresult
)

echo No Visual Studio found!
exit /b 1

:checkresult
if errorlevel 1 (
    echo.
    echo Build FAILED
    exit /b 1
)
echo.
echo Build complete! Output: bin\AutoHotkey64.exe
