@echo off
cd /d "%~dp0"
"C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe" AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /t:Build
