# Dot-source this file from a PowerShell profile. A native alias preserves
# interactive stdin, live pipelines, output redirection, and process exit codes.
param([string]$EnginePath = $env:AHK_CONSOLE_EXE)

# An explicit engine keeps isolated builds testable without replacing an
# installed executable or changing the user's PowerShell profile.
if (-not $EnginePath) {
    $EnginePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\AutoHotkey64Console.exe'
}
$ahkConsolePath = $EnginePath
if (-not (Test-Path -LiteralPath $ahkConsolePath -PathType Leaf)) {
    throw "The AutoHotkey console executable is missing: $ahkConsolePath"
}
$ahkConsolePath = (Resolve-Path -LiteralPath $ahkConsolePath).ProviderPath
if (Test-Path Function:\ahk) {
    Remove-Item Function:\ahk
}
Set-Alias -Name ahk -Value $ahkConsolePath -Scope Global
