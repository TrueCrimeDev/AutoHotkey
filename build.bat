@echo off
cd /d "%~dp0"
"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /t:Build
