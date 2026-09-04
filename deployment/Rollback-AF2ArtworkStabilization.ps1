[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'
$runtimeRoot = 'C:\RainmeterDenon'
$rainmeterIni = 'C:\Users\timmeh\AppData\Roaming\Rainmeter\Rainmeter.ini'
$manifestPath = Join-Path $BackupRoot 'manifest.csv'
$settingsPath = Join-Path $BackupRoot 'rainmeter-settings.json'

foreach ($required in @($manifestPath, $settingsPath, $rainmeterIni)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Rollback preflight failed; missing $required"
    }
}

$manifest = @(Import-Csv -LiteralPath $manifestPath)
foreach ($item in $manifest) {
    if ($item.Existed -eq 'True') {
        if (-not (Test-Path -LiteralPath $item.Backup -PathType Leaf)) {
            throw "Rollback preflight failed; missing $($item.Backup)"
        }
    }
}

$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$previousKeepOnScreen = [string]$settings.PreviousKeepOnScreen
if ($previousKeepOnScreen -notin @('0', '1')) {
    throw "Invalid saved KeepOnScreen value '$previousKeepOnScreen'."
}

foreach ($item in $manifest) {
    if ($item.Existed -eq 'True') {
        Copy-Item -LiteralPath $item.Backup -Destination $item.Destination -Force
    }
    else {
        Remove-Item -LiteralPath $item.Destination -Force -ErrorAction SilentlyContinue
    }
}

$encoding = [Text.Encoding]::Unicode
$content = [IO.File]::ReadAllText($rainmeterIni, $encoding)
$regex = [regex]::new('(?ms)(^\[Analog_Floating2\]\r?\n(?:(?!^\[).)*?^KeepOnScreen=)([^\r\n]*)')
$match = $regex.Match($content)
if (-not $match.Success) { throw 'Analog_Floating2 KeepOnScreen was not found in Rainmeter.ini.' }
$updated = $regex.Replace($content, { param($m) $m.Groups[1].Value + $previousKeepOnScreen }, 1)
$temporary = "$rainmeterIni.af2-rollback-$PID.tmp"
[IO.File]::WriteAllText($temporary, $updated, $encoding)
[IO.File]::Replace(
    $temporary,
    $rainmeterIni,
    (Join-Path $BackupRoot 'rainmeter\Rainmeter.rollback-pre-replace.ini')
)

& (Join-Path $runtimeRoot 'RestartTelemetry.cmd')
Start-Sleep -Seconds 8
& 'C:\Program Files\Rainmeter\Rainmeter.exe' !Refresh 'Analog_Floating2'

Write-Host "Rollback restored files from $BackupRoot"
Write-Host "Analog_Floating2 KeepOnScreen restored to $previousKeepOnScreen"
