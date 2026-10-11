[CmdletBinding()]
param(
    [ValidateSet('Deploy','Rollback')][string]$Action='Deploy',
    [string]$Root='C:\RainmeterDenon',
    [string]$SkinRoot='C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Analog_Floating2',
    [string]$BackupPath=''
)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
. (Join-Path $source 'Utilities\TelemetryProcessIdentity.ps1')
$files=@(
    @{Source='denon_status.ps1';Target=(Join-Path $Root 'denon_status.ps1')}
    @{Source='TelemetryManager.ps1';Target=(Join-Path $Root 'TelemetryManager.ps1')}
    @{Source='TelemetryProcessControl.ps1';Target=(Join-Path $Root 'TelemetryProcessControl.ps1')}
    @{Source='AvrWatchdog.ps1';Target=(Join-Path $Root 'AvrWatchdog.ps1')}
    @{Source='Utilities\AvrHealth.ps1';Target=(Join-Path $Root 'Utilities\AvrHealth.ps1')}
    @{Source='Analog_Floating2.ini';Target=(Join-Path $SkinRoot 'Analog_Floating2.ini')}
    @{Source='@Resources\Scripts\AvrHealthPresentation.lua';Target=(Join-Path $SkinRoot '@Resources\Scripts\AvrHealthPresentation.lua')}
)
function Stop-Affected {
    # Stop only the manager and the affected AVR workers. Keep metadata, Box1,
    # hotkeys and unrelated Rainmeter skins running throughout deployment.
    foreach($name in @('TelemetryManager.ps1','AvrWatchdog.ps1','denon_status.ps1')) {
        foreach($process in @(Get-TelemetryScriptProcesses -ScriptPath (Join-Path $Root $name))) {
            [void](Stop-TelemetryScriptProcess -Process $process)
        }
    }
    $deadline=[datetime]::UtcNow.AddSeconds(5)
    do {
        $remaining=@(foreach($name in @('TelemetryManager.ps1','AvrWatchdog.ps1','denon_status.ps1')) {Get-TelemetryScriptProcesses -ScriptPath (Join-Path $Root $name)})
        if (-not $remaining.Count) {return};Start-Sleep -Milliseconds 100
    } while([datetime]::UtcNow -lt $deadline)
    throw 'Affected processes did not stop; deployment aborted'
}
function Start-Affected {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f (Join-Path $Root 'TelemetryManager.ps1')))
    Start-Process 'C:\Program Files\Rainmeter\Rainmeter.exe' -WindowStyle Hidden -ArgumentList '[!Refresh "Analog_Floating2"]'
}
if($Action -eq 'Deploy') {
    foreach($file in $files) {
        $path=Join-Path $source $file.Source
        if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing source: $path"}
        if($path.EndsWith('.ps1')) {
            $tokens=$null;$errors=$null
            [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            if($errors.Count){throw "Parser error: $path"}
        }
    }
    if(-not $BackupPath){$BackupPath=Join-Path $Root ('Backups\AvrWatchdog-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
    if(Test-Path -LiteralPath $BackupPath){throw 'Backup folder already exists; refusing to overwrite rollback point'}
    [void][IO.Directory]::CreateDirectory($BackupPath)
    $manifest=@();$index=0
    foreach($file in $files) {
        $index++;$exists=Test-Path -LiteralPath $file.Target
        $backup=Join-Path $BackupPath "$index.pre"
        $hash=''
        if($exists){Copy-Item -LiteralPath $file.Target -Destination $backup;$hash=(Get-FileHash $file.Target).Hash
            if((Get-FileHash $backup).Hash -ne $hash){throw 'Backup hash mismatch'}}
        $manifest += [pscustomobject]@{Target=$file.Target;Backup=$backup;Existed=$exists;Hash=$hash;Source=$file.Source}
    }
    $manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $BackupPath 'manifest.json') -Encoding UTF8
    Stop-Affected
    try {
        foreach($file in $files) {
            [void][IO.Directory]::CreateDirectory((Split-Path $file.Target))
            Copy-Item -LiteralPath (Join-Path $source $file.Source) -Destination $file.Target -Force
            if((Get-FileHash $file.Target).Hash -ne (Get-FileHash (Join-Path $source $file.Source)).Hash){throw 'Deployment hash mismatch'}
        }
        Start-Affected
    } catch {
        $failure=$_
        & $PSCommandPath -Action Rollback -Root $Root -SkinRoot $SkinRoot -BackupPath $BackupPath
        throw $failure
    }
    "Deployment backup: $BackupPath"
} else {
    if(-not $BackupPath){throw 'Rollback requires an explicit BackupPath'}
    $manifest=Get-Content -LiteralPath (Join-Path $BackupPath 'manifest.json') -Raw | ConvertFrom-Json
    $allowed=@($files | ForEach-Object {[IO.Path]::GetFullPath($_.Target)})
    foreach($entry in $manifest) {
        if([IO.Path]::GetFullPath($entry.Target) -notin $allowed){throw 'Rollback target outside explicit deployment file list'}
        if($entry.Existed -and (Get-FileHash -LiteralPath $entry.Backup).Hash -ne $entry.Hash){throw 'Rollback backup missing or corrupt'}
    }
    Stop-Affected
    foreach($entry in $manifest) {
        if($entry.Existed){Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force}
        elseif(Test-Path -LiteralPath $entry.Target){Remove-Item -LiteralPath $entry.Target -Force}
    }
    Start-Affected
    'Rollback restored verified pre-deployment files.'
}
