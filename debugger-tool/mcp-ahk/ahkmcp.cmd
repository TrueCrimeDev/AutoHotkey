@echo off
REM ahkmcp - run the AHK MCP CLI tools (cli.ahk) from cmd / PowerShell.
REM Paths are relative to this file, so the repo can live anywhere.
REM Usage:  ahkmcp <tool> [args...]   e.g.  ahkmcp ast_outline C:\x.ahk
REM Engine: AHK_CUSTOM_EXE when set (only that), else the fork's console engine
REM bin\AutoHotkey64Console.exe, else the GUI bin\AutoHotkey64.exe. The console
REM engine is preferred: the shell waits for it and receives its output.
REM cli.ahk needs this fork's engine, so an exe without the fork's "CHECK PASS"
REM marker (stock AutoHotkey) is refused with exit 126 rather than run.
REM Pass absolute paths: the engine starts cli.ahk with its working directory
REM set to this folder, so a relative path resolves here, not where you are.
REM workspace_symbols without a root scans the directory you run this from.
REM No labels or goto: a checkout with LF line endings breaks label lookup.
setlocal DisableDelayedExpansion
if defined AHK_CUSTOM_EXE (
    set "AHKMCP_EXE=%AHK_CUSTOM_EXE%"
) else if exist "%~dp0..\..\bin\AutoHotkey64Console.exe" (
    set "AHKMCP_EXE=%~dp0..\..\bin\AutoHotkey64Console.exe"
) else (
    set "AHKMCP_EXE=%~dp0..\..\bin\AutoHotkey64.exe"
)
if not exist "%AHKMCP_EXE%" (
    >&2 echo ahkmcp: engine not found: "%AHKMCP_EXE%"
    >&2 echo ahkmcp: build it per BUILD.md, copy a release console engine into bin\, or set AHK_CUSTOM_EXE
    exit /b 127
)
REM The marker is the UTF-16 string "CHECK PASS"; each . matches its NUL bytes.
findstr /m /r /c:"C.H.E.C.K. .P.A.S.S" "%AHKMCP_EXE%" >nul 2>&1 || (
    >&2 echo ahkmcp: not this fork's engine ^(no CHECK PASS marker^): "%AHKMCP_EXE%"
    exit /b 126
)
set "AHKMCP_CLI=%~dp0cli.ahk"
REM Each exit names its code: a bare exit /b hands cmd /c callers 0, not the
REM engine's exit code.
if not "%~1"=="workspace_symbols" "%AHKMCP_EXE%" /Headless "%AHKMCP_CLI%" %*
if not "%~1"=="workspace_symbols" exit /b %ERRORLEVEL%

REM workspace_symbols: insert root=<current directory> right after the tool
REM name. cli.ahk applies arguments in order, so a root the caller gives, as
REM the first positional argument or as root=, still wins. A drive root such
REM as C:\ gets a trailing . so its backslash cannot escape the closing quote.
set "AHKMCP_ARGS=%*"
set "AHKMCP_CWD=%CD%"
if "%AHKMCP_CWD:~-1%"=="\" set "AHKMCP_CWD=%AHKMCP_CWD%."
setlocal EnableDelayedExpansion
"!AHKMCP_EXE!" /Headless "!AHKMCP_CLI!" %1 "root=!AHKMCP_CWD!" !AHKMCP_ARGS:*%1=!
exit /b !ERRORLEVEL!
