[CmdletBinding()]
param([string]$Root='C:\RainmeterDenon',[switch]$InjectCollectorFailure)
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\src'
. (Join-Path $source 'Utilities\AvrHealth.ps1')
. (Join-Path $source 'Utilities\TelemetryProcessIdentity.ps1')
function Wait-Trusted {
    $deadline=[datetime]::UtcNow.AddSeconds(30)
    do {
        $health=Read-AvrJson (Join-Path $Root 'avr_health.json')
        if($health.ResetAvr){throw 'Unexpected RESET AVR during healthy runtime validation'}
        if($health.Trusted -and (Get-AvrEpoch)-$health.Epoch -lt 8){return $health}
        Start-Sleep -Milliseconds 500
    } while([datetime]::UtcNow -lt $deadline)
    throw 'Runtime did not reach fresh independently verified state'
}
$health=Wait-Trusted
$ack=Read-AvrFields (Join-Path $Root 'avr_presentation_ack.txt')
if($ack.Session -ne $health.Session -or (Get-AvrEpoch)-[double]$ack.Epoch -gt 8){throw 'Rainmeter acknowledgment absent or stale'}
foreach($key in @('Source','Mode','Volume')) {
    if(($ack[$key] -replace '\s+dB$','') -ne [string]$health.Collector.Values.$key){throw "Rainmeter consumed value mismatch: $key"}
}
'PASS: production critical state independently verified; Rainmeter health reader updating and consumed values agree; no warning'
$unaffected=@{}
foreach($leaf in @('Box1Collector.ps1','Utilities\RainmeterRefreshHotkey.ps1','NowPlaying\NowPlayingRouter.ps1','NowPlaying\AppleMusicCollector.ps1','NowPlaying\WiiM-NowPlaying-Bridge.ps1')) {
    $unaffected[$leaf]=@((Get-TelemetryScriptProcesses -ScriptPath (Join-Path $Root $leaf)).ProcessId)
}
if($InjectCollectorFailure) {
    $path=Join-Path $Root 'denon_status.ps1'
    $processes=@(Get-TelemetryScriptProcesses -ScriptPath $path)
    if($processes.Count -ne 1){throw 'Expected exactly one Denon process before fault injection'}
    $oldPid=$processes[0].ProcessId
    [void](Stop-TelemetryScriptProcess -Process $processes[0])
    Start-Sleep -Seconds 5
    $health=Wait-Trusted
    $replacement=@(Get-TelemetryScriptProcesses -ScriptPath $path)
    if($replacement.Count -ne 1 -or $replacement[0].ProcessId -eq $oldPid){throw 'Manager did not replace terminated collector exactly once'}
    foreach($leaf in $unaffected.Keys) {
        $current=@((Get-TelemetryScriptProcesses -ScriptPath (Join-Path $Root $leaf)).ProcessId)
        if(($current -join ',') -ne ($unaffected[$leaf] -join ',')){throw "Healthy unrelated component changed during recovery: $leaf"}
    }
    'PASS: terminated production Denon collector automatically replaced; state freshly reverified; no RESET AVR; unrelated metadata/Box1/hotkey processes preserved'
}
foreach($leaf in @('TelemetryManager.ps1','AvrWatchdog.ps1','denon_status.ps1','DecoderCollector.ps1','Box1Collector.ps1','Utilities\RainmeterRefreshHotkey.ps1','NowPlaying\NowPlayingRouter.ps1')) {
    if(@(Get-TelemetryScriptProcesses -ScriptPath (Join-Path $Root $leaf)).Count -ne 1){throw "Duplicate or missing process: $leaf"}
}
'PASS: exactly one manager, watchdog, Denon, decoder, Box1, router and hotkey process'
$health | Select-Object Overall,Trusted,ResetAvr,Presentation,ChannelsFresh,DecoderFresh,DecoderRestartAttempted,LastIndependentVerification,LastSuccessfulRecovery
