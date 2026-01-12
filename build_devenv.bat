@echo off
echo Building with Visual Studio...
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe" "%~dp0AutoHotkeyx.sln" /Build "Release|x64" /Out "%~dp0build_log.txt"
echo.
echo Build log:
type "%~dp0build_log.txt"
echo.
if exist "%~dp0bin\AutoHotkey64.exe" (
    echo SUCCESS! Built: %~dp0bin\AutoHotkey64.exe
    dir "%~dp0bin\AutoHotkey64.exe"
) else (
    echo Build may still be in progress or failed. Check build_log.txt
)
