# Restart-runner: kills any prior instance of the target script, then relaunches it.
# Usage: .\run_ahk.ps1 [path\to\script.ahk]   (defaults to _.ahk next to this file)
param([string]$script = (Join-Path $PSScriptRoot '_.ahk'))
$ahkExe = Join-Path $PSScriptRoot '..\bin\AutoHotkey64.exe'

# Kill any running instances of this script
$processes = Get-WmiObject Win32_Process -Filter "Name='AutoHotkey64.exe'" |
    Where-Object { $_.CommandLine -like "*_.ahk*" }

if ($processes) {
    foreach ($proc in $processes) {
        Write-Host "Killing: _.ahk (PID: $($proc.ProcessId))"
        Stop-Process -Id $proc.ProcessId -Force
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "Starting: _.ahk"
Start-Process -FilePath $ahkExe -ArgumentList "`"$script`""
Write-Host "Done."
