@echo off
setlocal
cd /d "%~dp0"

set "VS18_VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
set "VS18_MSBUILD=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe"

if not exist "%VS18_VCVARS%" (
    echo Missing VS 18 toolchain: %VS18_VCVARS%
    exit /b 1
)

if not exist "%VS18_MSBUILD%" (
    echo Missing VS 18 MSBuild: %VS18_MSBUILD%
    exit /b 1
)

call "%VS18_VCVARS%" x64
if errorlevel 1 exit /b 1

"%VS18_MSBUILD%" AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64 /m
exit /b %errorlevel%
