@echo off
REM ahkmcp — run the AHK MCP CLI tools from cmd / PowerShell.
REM Paths are relative to this file, so the repo can live anywhere.
REM Usage:  ahkmcp <tool> [args...]   e.g.  ahkmcp ast_outline C:\x.ahk
"%~dp0..\..\bin\AutoHotkey64.exe" "%~dp0cli.ahk" %*
