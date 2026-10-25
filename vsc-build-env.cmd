@echo off

:: Sets up an MSVC developer environment for the VS Code build tasks, which run
:: cmd.exe /C call on this file, then the build command (see .vscode/tasks.json).
:: Target architecture: AHK_VS_ARCH = amd64 (default) or x86. The msbuild tasks
:: work with either, since /p:Platform selects the compiler; CMake/Ninja builds
:: use whatever cl.exe this environment puts on PATH.
if not defined AHK_VS_ARCH set "AHK_VS_ARCH=amd64"
if /i "%AHK_VS_ARCH%"=="x64" set "AHK_VS_ARCH=amd64"
set "AHK_VS_TGT=%AHK_VS_ARCH%"
if /i "%AHK_VS_ARCH%"=="amd64" set "AHK_VS_TGT=x64"

:: Reuse an existing developer environment only when it already targets that
:: architecture (VsDevCmd records it in VSCMD_ARG_TGT_ARCH) and provides both
:: the compiler and MSBuild.
if /i "%VSCMD_ARG_TGT_ARCH%"=="%AHK_VS_TGT%" (
    where cl >nul 2>nul && where msbuild >nul 2>nul && exit /b 0
)

:: Allow the path to vsdevcmd to be provided by our caller
if exist "%vsdevcmd%" "%vsdevcmd%" -arch=%AHK_VS_ARCH% -host_arch=amd64
:: If we're still running, must be no vsdevcmd

if "%ProgramFiles(x86)%"=="" set ProgramFiles(x86)=%ProgramFiles%
set vswhere="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist %vswhere% (
    echo vswhere.exe not found; unable to locate build tools.
    exit /b 1
)

:: Each match transfers control to vsdevcmd.bat (no "call"), so its environment
:: stays in effect for the build command that follows.
:: This should work for Visual Studio
for /f "usebackq delims=" %%i in (`%vswhere% -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -find *\Tools\vsdevcmd.bat`) do "%%i" -arch=%AHK_VS_ARCH% -host_arch=amd64
:: This should work with Visual Studio Build Tools
for /f "usebackq delims=" %%i in (`%vswhere% -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -find *\Tools\vsdevcmd.bat`) do "%%i" -arch=%AHK_VS_ARCH% -host_arch=amd64
:: As a last resort, try without specifying the required workload
for /f "usebackq delims=" %%i in (`%vswhere% -latest -products * -find *\Tools\vsdevcmd.bat`) do "%%i" -arch=%AHK_VS_ARCH% -host_arch=amd64
:: If we're still running, vsdevcmd wasn't executed
echo Unable to locate build tools.
exit /b 1
