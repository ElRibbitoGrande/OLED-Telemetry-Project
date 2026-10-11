# Execute the actual watchdog loop on a virtual clock with injected transport.
# No physical AVR, process termination, Rainmeter command or sleep is involved.
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\src'
$rootBase=Join-Path $PSScriptRoot ('captures\Escalation-'+[guid]::NewGuid())
$content=Get-Content (Join-Path $source 'AvrWatchdog.ps1') -Raw
$content=$content.Replace(". (Join-Path `$PSScriptRoot 'Utilities\AvrHealth.ps1')", ". '$source\Utilities\AvrHealth.ps1'")
$content=$content.Replace(". (Join-Path `$PSScriptRoot 'Utilities\TelemetryProcessIdentity.ps1')", ". '$source\Utilities\TelemetryProcessIdentity.ps1'")
$mocks=@'
$script:virtualEpoch=2000000000
function Get-AvrEpoch {return $script:virtualEpoch}
function Start-Sleep {
    param($Seconds,$Milliseconds)
    $script:virtualEpoch+=2
    if($script:virtualEpoch-2000000000 -ge 260 -or $AvrHost -in @('healthy','healthy-collector')) {
        $o=Read-AvrJson (Join-Path $Root 'avr_collector_observation.json')
        if($o) {
            $o.Epoch=$script:virtualEpoch
            foreach($key in @('Power','Source','Mode','Volume')) {$o.Observed.$key=$script:virtualEpoch}
            Write-AvrJson (Join-Path $Root 'avr_collector_observation.json') $o
        }
    }
}
function Get-AvrIdentity {param($AvrHost) return $AvrHost -ne 'network-failure'}
function Get-AvrVerification {
    param($AvrHost,$Port,[switch]$Comprehensive)
    $elapsed=$script:virtualEpoch-2000000000
    $valid=$AvrHost -eq 'healthy' -or $elapsed -ge 260
    if($valid -or $AvrHost -eq 'healthy-collector') {
        $observation=@{Epoch=$script:virtualEpoch;Observed=@{Power=$script:virtualEpoch;Source=$script:virtualEpoch;Mode=$script:virtualEpoch;Volume=$script:virtualEpoch};Values=@{Power='ON';Source='HTPC';Mode='DOLBY SURROUND';Volume='-19.5'}}
        Write-AvrJson (Join-Path $Root 'avr_collector_observation.json') $observation
        [IO.File]::WriteAllText((Join-Path $Root 'denon_status.txt'),"Source=HTPC`nMode=DOLBY SURROUND`nVolume=-19.5 dB`n")
    }
    return @{Epoch=$script:virtualEpoch;Valid=$valid;Standby=($AvrHost -eq 'standby');TcpConnected=$true;ChannelsComplete=$valid;Values=@{Power='ON';Source='HTPC';Mode='DOLBY SURROUND';Volume='-19.5'};Error=$(if($valid){''}else{'Injected missing replies'})}
}
'@
$content=$content.Replace('$created = $false',($mocks+"`n`$created = `$false"))
[void][IO.Directory]::CreateDirectory($rootBase)
$harness=Join-Path $rootBase 'harness.ps1'
[IO.File]::WriteAllText($harness,$content,[Text.UTF8Encoding]::new($false))
foreach($scenario in @('avr-control','network-failure','healthy-collector','standby','healthy')) {
    $fixtureRoot=Join-Path $rootBase $scenario
    [void][IO.Directory]::CreateDirectory($fixtureRoot)
    Copy-Item (Join-Path $source 'denon_status.ps1') $fixtureRoot
    # A previous successful query is historical eligibility evidence only.
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'avr_health.json'),'{"BaselineVerified":true}')
    & $harness -Root $fixtureRoot -AvrHost $scenario -MaximumCycles 160 -DisableRecovery
    $records=@(Get-Content (Join-Path $fixtureRoot 'Logs\AvrWatchdog.jsonl') | ForEach-Object {$_|ConvertFrom-Json})
    $warnings=@($records|Where-Object {$_.Event -eq 'Health' -and $_.Detail.ResetAvr})
    if(($scenario -eq 'avr-control') -ne ($warnings.Count -gt 0)) {throw "Wrong warning behavior: $scenario"}
    $health=Get-Content (Join-Path $fixtureRoot 'avr_health.json') -Raw | ConvertFrom-Json
    if($health.ResetAvr -or -not $health.Trusted) {throw "Recovery did not clear warning and verify state: $scenario"}
    $actions=@($records|Where-Object {$_.Event -eq 'RecoveryAttempt'})
    if($actions.Count -gt 3) {throw "Recovery oscillation: $scenario"}
    "PASS: $scenario prolonged failure, bounded escalation, warning criteria, automatic clearing and recovery"
}
"Evidence preserved at $rootBase"
