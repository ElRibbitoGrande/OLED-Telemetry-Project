[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Repo = 'C:\OLED-Telemetry-Project'
$SourceRoot = Join-Path $Repo 'src'
$DestinationRoot = 'C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Analog_Floating2'
$RainmeterIni = 'C:\Users\timmeh\AppData\Roaming\Rainmeter\Rainmeter.ini'
$ProductionIni = 'C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Desktop VU-Meter 3\Skins\Analog_Floating.ini'
$ExpectedProductionHash = 'B09135DAB2AEAE49A8865652A7F0C30CCC31567555938108B523F752F690A76B'
$Python = 'C:\Users\timmeh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$CaptureHelper = Join-Path $SourceRoot '@Resources\AnalogFloating2Tools\Capture-AF2.py'
$ReferenceRoot = Join-Path $Repo 'docs\references'

$RequiredArtifacts = @(
    'Analog_Floating2_blueprint_coordinates.csv'
    'Analog_Floating2_boundary_inventory.csv'
    'Analog_Floating2_failed_render_defects.csv'
    'Analog_Floating2_overlay.png'
    'Analog_Floating2_difference.png'
)
$RequiredFiles = @(
    'Analog_Floating2.ini'
    '@Resources\MeterStyles\AnalogFloating2\Speakers.inc'
    '@Resources\MeterStyles\AnalogFloating2\VU.inc'
)
$ImageRelativeRoot = '@Resources\Images\AnalogFloating2'
$ImageSourceRoot = Join-Path $SourceRoot $ImageRelativeRoot
$RequiredImages = @(
    'Windows.png'
    'APPLE_MUSIC.png'
    'Schiit.png'
    'Plex.png'
    'DOLBY_ATMOS.png'
    'DTS_X.png'
    'NONE.png'
    'VU_Needle.png'
)

# Preflight is deliberately complete before backup creation or any deployment write.
$Missing = [System.Collections.Generic.List[string]]::new()
foreach ($Name in $RequiredArtifacts) {
    $Path = Join-Path $ReferenceRoot $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $Missing.Add($Path) }
}
foreach ($Name in $RequiredFiles) {
    $Path = Join-Path $SourceRoot $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $Missing.Add($Path) }
}
if (-not (Test-Path -LiteralPath $ImageSourceRoot -PathType Container)) {
    $Missing.Add($ImageSourceRoot)
} else {
    foreach ($Name in $RequiredImages) {
        $Path = Join-Path $ImageSourceRoot $Name
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $Missing.Add($Path) }
    }
}
foreach ($Path in @($RainmeterIni, $ProductionIni, $Python, $CaptureHelper)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $Missing.Add($Path) }
}
if ($Missing.Count -gt 0) {
    throw "PREDEPLOY FAIL - required input missing; nothing was copied:`n$($Missing -join "`n")"
}

$ProductionPre = (Get-FileHash -Algorithm SHA256 -LiteralPath $ProductionIni).Hash
if ($ProductionPre -ne $ExpectedProductionHash) {
    throw "PREDEPLOY FAIL - production hash is $ProductionPre, expected $ExpectedProductionHash"
}
$RainmeterPre = (Get-FileHash -Algorithm SHA256 -LiteralPath $RainmeterIni).Hash

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupRoot = Join-Path $env:TEMP "AF2_predeploy_$Stamp"
New-Item -ItemType Directory -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $RainmeterIni -Destination (Join-Path $BackupRoot 'Rainmeter.ini.pre') -Force

$DeployList = [System.Collections.Generic.List[object]]::new()
foreach ($Relative in $RequiredFiles) {
    $DeployList.Add([pscustomobject]@{
        Relative = $Relative
        Source = Join-Path $SourceRoot $Relative
        Destination = Join-Path $DestinationRoot $Relative
    })
}
foreach ($Image in Get-ChildItem -LiteralPath $ImageSourceRoot -File) {
    $Relative = Join-Path $ImageRelativeRoot $Image.Name
    $DeployList.Add([pscustomobject]@{
        Relative = $Relative
        Source = $Image.FullName
        Destination = Join-Path $DestinationRoot $Relative
    })
}

$Manifest = [System.Collections.Generic.List[object]]::new()
foreach ($Item in $DeployList) {
    $Existed = Test-Path -LiteralPath $Item.Destination -PathType Leaf
    $Backup = ''
    if ($Existed) {
        $Backup = Join-Path $BackupRoot $Item.Relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $Backup) -Force | Out-Null
        Copy-Item -LiteralPath $Item.Destination -Destination $Backup -Force
    }
    $Manifest.Add([pscustomobject]@{
        Relative = $Item.Relative
        Existed = $Existed
        Backup = $Backup
        Destination = $Item.Destination
    })
}
$ManifestPath = Join-Path $BackupRoot 'manifest.csv'
$Manifest | Export-Csv -LiteralPath $ManifestPath -NoTypeInformation

$HashRows = [System.Collections.Generic.List[object]]::new()
$Result = 'FAIL'
$CaptureResult = $null
$ProductionPost = $null
$RainmeterPost = $null

try {
    foreach ($Item in $DeployList) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Item.Destination) -Force | Out-Null
        Copy-Item -LiteralPath $Item.Source -Destination $Item.Destination -Force
        $SourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Item.Source).Hash
        $DeployedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Item.Destination).Hash
        $HashRows.Add([pscustomobject]@{
            File = $Item.Relative
            SourceSHA256 = $SourceHash
            DeployedSHA256 = $DeployedHash
        })
        if ($SourceHash -ne $DeployedHash) {
            throw "DEPLOY FAIL - SHA-256 mismatch for $($Item.Relative)"
        }
    }

    # The only Rainmeter bang issued is a refresh of Analog_Floating2.
    & 'C:\Program Files\Rainmeter\Rainmeter.exe' !Refresh 'Analog_Floating2'
    Start-Sleep -Seconds 3

    & $Python $CaptureHelper $ReferenceRoot (Join-Path $ReferenceRoot 'Analog_Floating2_blueprint.png')
    if ($LASTEXITCODE -ne 0) { throw "VALIDATION FAIL - capture helper exited $LASTEXITCODE" }
    $CaptureResult = Get-Content -LiteralPath (Join-Path $ReferenceRoot 'Analog_Floating2_capture_result.json') -Raw |
        ConvertFrom-Json
    if (
        $CaptureResult.Original.X -ne $CaptureResult.Restored.X -or
        $CaptureResult.Original.Y -ne $CaptureResult.Restored.Y -or
        $CaptureResult.Original.Width -ne $CaptureResult.Restored.Width -or
        $CaptureResult.Original.Height -ne $CaptureResult.Restored.Height
    ) {
        throw 'VALIDATION FAIL - Analog_Floating2 was not restored to its exact original rectangle'
    }

    $Result = 'PASS'
}
finally {
    $RainmeterPost = (Get-FileHash -Algorithm SHA256 -LiteralPath $RainmeterIni).Hash
    if ($RainmeterPost -ne $RainmeterPre) {
        Copy-Item -LiteralPath (Join-Path $BackupRoot 'Rainmeter.ini.pre') -Destination $RainmeterIni -Force
        $RainmeterPost = (Get-FileHash -Algorithm SHA256 -LiteralPath $RainmeterIni).Hash
        if ($RainmeterPost -ne $RainmeterPre) {
            $Result = 'FAIL'
            Write-Host "POSTDEPLOY FAIL - Rainmeter.ini changed and restoration failed: $RainmeterPost"
        }
    }

    $ProductionPost = (Get-FileHash -Algorithm SHA256 -LiteralPath $ProductionIni).Hash
    if ($ProductionPost -ne $ExpectedProductionHash -or $ProductionPost -ne $ProductionPre) {
        $Result = 'FAIL'
        Write-Host "POSTDEPLOY FAIL - production Analog_Floating.ini changed: $ProductionPost"
    }

    $Rollback = "`$m=Import-Csv -LiteralPath '$ManifestPath'; foreach (`$x in `$m) { if (`$x.Existed -eq 'True') { Copy-Item -LiteralPath `$x.Backup -Destination `$x.Destination -Force } else { Remove-Item -LiteralPath `$x.Destination -Force -ErrorAction SilentlyContinue } }"

    Write-Host "BACKUP: $BackupRoot"
    Write-Host 'FILES CREATED OR REPLACED:'
    $Manifest | Select-Object Relative, Existed, Destination | Format-Table -AutoSize
    Write-Host 'SOURCE / DEPLOYED HASHES:'
    $HashRows | Format-Table -AutoSize
    Write-Host "PRODUCTION PRE:  $ProductionPre"
    Write-Host "PRODUCTION POST: $ProductionPost"
    Write-Host "RAINMETER.INI PRE:  $RainmeterPre"
    Write-Host "RAINMETER.INI POST: $RainmeterPost"
    if ($CaptureResult) {
        Write-Host "ORIGINAL AF2:   $($CaptureResult.Original | ConvertTo-Json -Compress)"
        Write-Host "VALIDATION AF2: $($CaptureResult.Validation | ConvertTo-Json -Compress)"
        Write-Host "RESTORED AF2:   $($CaptureResult.Restored | ConvertTo-Json -Compress)"
        Write-Host "SCREENSHOT: $($CaptureResult.Desktop)"
        Write-Host "CROP: $($CaptureResult.Crop)"
        Write-Host "OVERLAY: $($CaptureResult.Overlay)"
        Write-Host "DIFFERENCE: $($CaptureResult.Difference)"
    }
    Write-Host "ROLLBACK: $Rollback"
    Write-Host "RESULT: $Result"
}

if ($Result -ne 'PASS') { throw 'Analog_Floating2 deployment validation failed' }
