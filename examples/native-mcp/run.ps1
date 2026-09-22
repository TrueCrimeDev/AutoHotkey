param(
    [ValidateSet('All', '1', '2', '3', '4')]
    [string]$Demo = 'All',
    [string]$Engine = (Join-Path $PSScriptRoot '..\..\bin_review\AutoHotkey64Console.exe'),
    [string]$Text = "  Meeting`t notes:   follow up   tomorrow.  ",
    [switch]$FailTest
)

$ErrorActionPreference = 'Stop'
$enginePath = (Resolve-Path -LiteralPath $Engine).Path
if ($FailTest -and $Demo -ne '4') {
    throw 'Use -Demo 4 with -FailTest. The intentional failure returns exit 14.'
}
& $enginePath --version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$examples = @(
    '01_find_function.ahk',
    '02_check_then_run.ahk',
    '03_explain_failure.ahk',
    '04_run_tests.ahk'
)
$selection = if ($Demo -eq 'All') { 0..3 } else { @([int]$Demo - 1) }
foreach ($index in $selection) {
    $scriptPath = Join-Path $PSScriptRoot $examples[$index]
    Write-Host "`n$($examples[$index])" -ForegroundColor Cyan
    $scriptArguments = @()
    if ($index -eq 1) { $scriptArguments = @($Text) }
    if ($index -eq 3 -and $FailTest) { $scriptArguments = @('--fail') }
    & $enginePath /Headless /Diag=json $scriptPath @scriptArguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Host "`nSelected demos completed." -ForegroundColor Green
