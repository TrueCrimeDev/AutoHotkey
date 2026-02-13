@echo off
setlocal

REM Set up paths manually to avoid dependency issues
set "VSINSTALLDIR=C:\Program Files\Microsoft Visual Studio\2022\Community\"
set "VCToolsInstallDir=%VSINSTALLDIR%VC\Tools\MSVC\14.30.30705\"
set "WindowsSdkDir=C:\Program Files (x86)\Windows Kits\10\"

REM Find and use latest VC tools
for /d %%i in ("%VSINSTALLDIR%VC\Tools\MSVC\*") do set "VCToolsInstallDir=%%i\"

cd /d "%~dp0"
echo Using VC Tools from: %VCToolsInstallDir%

REM Use cl.exe directly or try vcvarsall
call "%VSINSTALLDIR%VC\Auxiliary\Build\vcvarsall.bat" x64

echo.
echo Environment set. Building...
msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /t:Build /m

if exist "bin\AutoHotkey64.exe" (
    echo.
    echo ========== SUCCESS ==========
    dir bin\AutoHotkey64.exe
) else (
    echo.
    echo Build may have failed. Check above for errors.
)
pause
