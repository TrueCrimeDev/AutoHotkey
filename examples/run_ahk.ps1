$ahkExe = "C:\Users\uphol\Documents\Design\Coding\AutoHotkey\bin\AutoHotkey64.exe"
$script = "C:\Users\uphol\Documents\Autohotkey\_.ahk"

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
