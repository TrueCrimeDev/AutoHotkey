# Dot-source this file from a PowerShell profile. A native alias preserves
# interactive stdin, live pipelines, output redirection, and process exit codes.
$ahkConsolePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\AutoHotkey64Console.exe'
if (-not (Test-Path -LiteralPath $ahkConsolePath -PathType Leaf)) {
    throw "The AutoHotkey console executable is missing: $ahkConsolePath"
}
if (Test-Path Function:\ahk) {
    Remove-Item Function:\ahk
}
Set-Alias -Name ahk -Value $ahkConsolePath -Scope Global
