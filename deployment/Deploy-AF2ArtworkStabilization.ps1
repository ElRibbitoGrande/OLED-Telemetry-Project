[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = 'C:\RainmeterDenon'
$skinRoot = 'C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Analog_Floating2'
$rainmeterIni = 'C:\Users\timmeh\AppData\Roaming\Rainmeter\Rainmeter.ini'
$backupRoot = Join-Path $runtimeRoot ('Backups\AF2-Artwork-Stabilization\{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))

function Set-AF2KeepOnScreen {
    param([string]$Path, [ValidateSet('0', '1')][string]$Value, [string]$TransactionBackup)

    $encoding = [Text.Encoding]::Unicode
    $content = [IO.File]::ReadAllText($Path, $encoding)
    $regex = [regex]::new('(?ms)(^\[Analog_Floating2\]\r?\n(?:(?!^\[).)*?^KeepOnScreen=)([^\r\n]*)')
    $match = $regex.Match($content)
    if (-not $match.Success) { throw 'Analog_Floating2 KeepOnScreen was not found in Rainmeter.ini.' }
    $previous = $match.Groups[2].Value
    if ($previous -ne $Value) {
        $updated = $regex.Replace($content, { param($m) $m.Groups[1].Value + $Value }, 1)
        $temporary = "$Path.af2-deploy-$PID.tmp"
        [IO.File]::WriteAllText($temporary, $updated, $encoding)
        [IO.File]::Replace($temporary, $Path, $TransactionBackup)
    }
    return $previous
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Path)

    $stream = $null
    $algorithm = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $algorithm = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        if ($algorithm) { $algorithm.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

$deploy = @(
    [pscustomobject]@{ Source = 'src\Analog_Floating2.ini'; Destination = Join-Path $skinRoot 'Analog_Floating2.ini' },
    [pscustomobject]@{ Source = 'src\@Resources\Includes\DashboardState.inc'; Destination = Join-Path $skinRoot '@Resources\Includes\DashboardState.inc' },
    [pscustomobject]@{ Source = 'src\@Resources\MeterStyles\AnalogFloating2\Speakers.inc'; Destination = Join-Path $skinRoot '@Resources\MeterStyles\AnalogFloating2\Speakers.inc' },
    [pscustomobject]@{ Source = 'src\@Resources\Scripts\NowPlayingDiagnostic.lua'; Destination = Join-Path $skinRoot '@Resources\Scripts\NowPlayingDiagnostic.lua' },
    [pscustomobject]@{ Source = 'src\@Resources\Scripts\AF2PixelShift.lua'; Destination = Join-Path $skinRoot '@Resources\Scripts\AF2PixelShift.lua' },
    [pscustomobject]@{ Source = 'src\NowPlaying\AppleMusicCollector.ps1'; Destination = Join-Path $runtimeRoot 'NowPlaying\AppleMusicCollector.ps1' },
    [pscustomobject]@{ Source = 'src\NowPlaying\WiiM-NowPlaying-Bridge.ps1'; Destination = Join-Path $runtimeRoot 'NowPlaying\WiiM-NowPlaying-Bridge.ps1' },
    [pscustomobject]@{ Source = 'src\Utilities\RainmeterRefreshHotkey.ps1'; Destination = Join-Path $runtimeRoot 'Utilities\RainmeterRefreshHotkey.ps1' },
    [pscustomobject]@{ Source = 'src\Utilities\ArtworkDiagnosticCapture.ps1'; Destination = Join-Path $runtimeRoot 'Utilities\ArtworkDiagnosticCapture.ps1' }
)

$missing = foreach ($item in $deploy) {
    $sourcePath = Join-Path $repoRoot $item.Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { $sourcePath }
}
if ($missing) { throw "Preflight failed; missing source files:`n$($missing -join "`n")" }
foreach ($required in @(
    (Join-Path $runtimeRoot 'RestartTelemetry.cmd'),
    $rainmeterIni,
    'C:\Program Files\Rainmeter\Rainmeter.exe'
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Preflight failed; missing $required" }
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$rainmeterBackupDirectory = Join-Path $backupRoot 'rainmeter'
New-Item -ItemType Directory -Path $rainmeterBackupDirectory -Force | Out-Null
Copy-Item -LiteralPath $rainmeterIni -Destination (Join-Path $rainmeterBackupDirectory 'Rainmeter.ini') -Force
$previousKeepOnScreen = Set-AF2KeepOnScreen -Path $rainmeterIni -Value '0' `
    -TransactionBackup (Join-Path $rainmeterBackupDirectory 'Rainmeter.pre-replace.ini')
[pscustomobject]@{ PreviousKeepOnScreen = $previousKeepOnScreen } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupRoot 'rainmeter-settings.json') -Encoding UTF8

$manifest = [Collections.Generic.List[object]]::new()
foreach ($item in $deploy) {
    $sourcePath = Join-Path $repoRoot $item.Source
    $relativeBackup = if ($item.Destination.StartsWith($runtimeRoot, [StringComparison]::OrdinalIgnoreCase)) {
        'runtime' + $item.Destination.Substring($runtimeRoot.Length)
    }
    else {
        'skin' + $item.Destination.Substring($skinRoot.Length)
    }
    $backupPath = Join-Path $backupRoot $relativeBackup.TrimStart('\')
    $existed = Test-Path -LiteralPath $item.Destination -PathType Leaf
    if ($existed) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
        Copy-Item -LiteralPath $item.Destination -Destination $backupPath -Force
    }
    $manifest.Add([pscustomobject]@{
        Source = $sourcePath; Destination = $item.Destination
        Existed = $existed; Backup = $backupPath
        PreviousSHA256 = $(if ($existed) { Get-Sha256Hex -Path $item.Destination } else { '' })
    })
}
$manifestPath = Join-Path $backupRoot 'manifest.csv'
$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation

foreach ($item in $manifest) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $item.Destination) -Force | Out-Null
    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force
    $sourceHash = Get-Sha256Hex -Path $item.Source
    $deployedHash = Get-Sha256Hex -Path $item.Destination
    if ($sourceHash -ne $deployedHash) { throw "Deployment hash mismatch: $($item.Destination)" }
}

& (Join-Path $runtimeRoot 'RestartTelemetry.cmd')
Start-Sleep -Seconds 8
& 'C:\Program Files\Rainmeter\Rainmeter.exe' !Refresh 'Analog_Floating2'
Start-Sleep -Seconds 3

$results = foreach ($item in $manifest) {
    [pscustomobject]@{
        Destination = $item.Destination
        SHA256 = Get-Sha256Hex -Path $item.Destination
        MatchesSource = ((Get-Sha256Hex -Path $item.Source) -eq
            (Get-Sha256Hex -Path $item.Destination))
    }
}
$results | Format-Table -AutoSize

$rollbackScript = Join-Path $repoRoot 'deployment\Rollback-AF2ArtworkStabilization.ps1'
$rollback = "& '$rollbackScript' -BackupRoot '$backupRoot'"
Write-Host "BACKUP: $backupRoot"
Write-Host "MANIFEST: $manifestPath"
Write-Host "ROLLBACK: $rollback"
