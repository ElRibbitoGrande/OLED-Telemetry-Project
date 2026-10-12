[CmdletBinding()]
param([ValidateSet('Deploy','Rollback')][string]$Action='Deploy',[string]$BackupPath='', [switch]$IncludeCollector)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
$skin='C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Analog_Floating2'
$files=@('MeterResponse.inc','Box1VUComparisonCapture.lua','SignalAcquisition.inc','AdaptiveGain.lua','AdaptiveGainCore.lua')
$entries=@(foreach($name in $files){@{Source=(Join-Path $source "@Resources\VU\$name");Target=(Join-Path $skin "@Resources\VU\$name")}})
$entries+=@{Source=(Join-Path $source 'Analog_Floating2.ini');Target=(Join-Path $skin 'Analog_Floating2.ini')}
if($IncludeCollector){$entries+=@{Source=(Join-Path $source 'Box1Collector.ps1');Target='C:\RainmeterDenon\Box1Collector.ps1'}}
if($Action -eq 'Deploy') {
    if(-not $BackupPath){$BackupPath=Join-Path $PSScriptRoot ('captures\VU-latency-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
    if(Test-Path -LiteralPath $BackupPath){throw 'Refusing to overwrite existing backup'}
    [void][IO.Directory]::CreateDirectory($BackupPath)
    $manifest=@();$index=0
    foreach($entry in $entries){$index++;$path=Join-Path $BackupPath "$index.pre";$exists=Test-Path -LiteralPath $entry.Target;$hash=''
        if($exists){Copy-Item -LiteralPath $entry.Target -Destination $path;$hash=(Get-FileHash $entry.Target).Hash;if((Get-FileHash $path).Hash -ne $hash){throw 'Backup hash mismatch'}}
        $manifest+=[pscustomobject]@{Source=$entry.Source;Target=$entry.Target;Existed=$exists;Backup=$path;Hash=$hash}
    }
    $manifest|ConvertTo-Json|Set-Content (Join-Path $BackupPath 'manifest.json') -Encoding UTF8
} else {
    if(-not $BackupPath){throw 'Explicit rollback BackupPath required'}
    $manifest=Get-Content (Join-Path $BackupPath 'manifest.json') -Raw|ConvertFrom-Json
    $allowed=@($entries.Target)+'C:\RainmeterDenon\Box1Collector.ps1'
    foreach($entry in $manifest){if($entry.Target -notin $allowed){throw 'Rollback target outside VU file list'};if($entry.Existed -and (Get-FileHash $entry.Backup).Hash -ne $entry.Hash){throw 'Backup missing or corrupt'}}
}
if(@($manifest|Where-Object {$_.Target -eq 'C:\RainmeterDenon\Box1Collector.ps1'}).Count){
    . (Join-Path $source 'Utilities\TelemetryProcessIdentity.ps1')
    # Copy before exact-process stop; manager starts the updated collector normally.
}
foreach($entry in $manifest){
    if($Action -eq 'Deploy'){Copy-Item -LiteralPath $entry.Source -Destination $entry.Target -Force;if((Get-FileHash $entry.Source).Hash -ne (Get-FileHash $entry.Target).Hash){throw 'Deployment hash mismatch'}}
    elseif($entry.Existed){Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force}
    # New diagnostic Lua files can remain inert after restoring their include.
}
if(@($manifest|Where-Object {$_.Target -eq 'C:\RainmeterDenon\Box1Collector.ps1'}).Count){foreach($p in @(Get-TelemetryScriptProcesses -ScriptPath 'C:\RainmeterDenon\Box1Collector.ps1')){[void](Stop-TelemetryScriptProcess -Process $p)}}
Start-Process 'C:\Program Files\Rainmeter\Rainmeter.exe' -WindowStyle Hidden -ArgumentList '[!Refresh "Analog_Floating2"]'
"$Action complete. Verified rollback manifest: $BackupPath"
