[CmdletBinding()]
param(
    [string]$Root = 'C:\RainmeterDenon',
    [string]$AvrHost = '',
    [int]$Port = 23,
    [int]$VerificationSeconds = 45,
    [int]$MaximumCycles = 0,
    [switch]$DisableRecovery,
    [string]$WatchdogMutexName = 'Local\RainmeterDenonAvrWatchdog'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Utilities\AvrHealth.ps1')
. (Join-Path $PSScriptRoot 'Utilities\TelemetryProcessIdentity.ps1')
$collector = Join-Path $Root 'denon_status.ps1'
Import-AvrValueParsers $collector
if (-not $AvrHost) {
    $configuration = Get-Content -LiteralPath $collector -Raw
    if ($configuration -match '(?m)^\$ip\s*=\s*"([^"]+)"') { $AvrHost = $Matches[1] }
    else { throw 'AVR address absent in collector configuration' }
}
$created = $false
$mutex = [Threading.Mutex]::new($true, $WatchdogMutexName, [ref]$created)
if (-not $created) { $mutex.Dispose(); exit }
$statusPath = Join-Path $Root 'avr_health.json'
$displayPath = Join-Path $Root 'avr_health_display.txt'
$logPath = Join-Path $Root 'Logs\AvrWatchdog.jsonl'
[void][IO.Directory]::CreateDirectory((Split-Path $logPath))
$session = [guid]::NewGuid().ToString()
$previousHealth = Read-AvrJson $statusPath
$nextVerify = 0; $nextComprehensive = 0; $lastVerify = 0; $lastComprehensive = 0
$failures = 0; $failureStart = 0; $baseline = $false; $level = 0
if ($previousHealth -and ($previousHealth.BaselineVerified -or $previousHealth.LastIndependentVerification -gt 0)) { $baseline = $true }
$lastVerifiedPower = [string]$previousHealth.LastVerifiedPower
$deviceFingerprint = [string]$previousHealth.DeviceFingerprint
if (-not $lastVerifiedPower -and $previousHealth.Collector.Values.Power) { $lastVerifiedPower=[string]$previousHealth.Collector.Values.Power }
$nextRecovery = 0; $lastRecovery = ''; $recoveredAt = 0; $faultSince = 0
$lastClass = ''; $lastLog = 0; $verification = $null; $mismatches = @()
$reconnectAttempted = $false; $restartAttempted = $false; $lastRestart = 0
$lastPresentationRepair = 0; $presentationAttempts = 0; $cycle = 0
$decoderRestartAttempted = $false; $lastDecoderRestart = 0
$networkEvidence = $null
function Write-WatchdogEvent([string]$Event, $Detail) {
    try {
        if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB) {
            Move-Item -LiteralPath $logPath -Destination "$logPath.1" -Force
        }
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (@{Epoch=Get-AvrEpoch;Event=$Event;Detail=$Detail} | ConvertTo-Json -Compress -Depth 8)
    } catch {}
}
function Request-AvrRecovery([string]$Action) {
    Write-AvrJson (Join-Path $Root 'avr_recovery_request.json') @{Token=[guid]::NewGuid().ToString();Created=Get-AvrEpoch;Action=$Action}
}
function Invoke-AvrPresentationRepair([switch]$Refresh) {
    $executable = 'C:\Program Files\Rainmeter\Rainmeter.exe'
    if (-not (Test-Path $executable)) { return }
    $argument = '[!UpdateMeasure * "Analog_Floating2"][!UpdateMeter * "Analog_Floating2"][!Redraw "Analog_Floating2"]'
    if ($Refresh) { $argument = '[!Refresh "Analog_Floating2"]' }
    $process = Start-Process -FilePath $executable -WindowStyle Hidden -ArgumentList $argument -PassThru
    $process.Dispose()
}
try {
    while ($MaximumCycles -le 0 -or $cycle -lt $MaximumCycles) {
        $cycle++
        try {
            $now = Get-AvrEpoch
            $observation = Read-AvrJson (Join-Path $Root 'avr_collector_observation.json')
            $fresh = Get-AvrCollectorFresh $observation $now
            $identity = $false
            if ($now -ge $nextVerify) {
                $comprehensive = $now -ge $nextComprehensive
                $verification = Get-AvrVerification -AvrHost $AvrHost -Port $Port -Comprehensive:$comprehensive
                $now = Get-AvrEpoch
                if ($verification.Valid) {
                    $networkEvidence = $null
                    $lastVerifiedPower = [string]$verification.Values.Power
                    if (-not $deviceFingerprint) {
                        $fingerprint = Get-AvrIdentity -AvrHost $AvrHost -FingerprintOnly
                        if ($fingerprint -is [string] -and $fingerprint.Length -eq 64) { $deviceFingerprint=$fingerprint }
                    }
                    $lastVerify = $now; $baseline = $true; $failures = 0; $failureStart = 0
                    if ($comprehensive -and $verification.ChannelsComplete) {
                        $lastComprehensive = $now; $nextComprehensive = $now + 600
                        Request-AvrRecovery 'Reconcile'
                    }
                } elseif ($verification.Standby) {
                    $lastVerifiedPower = 'STANDBY'
                    $failures=0; $failureStart=0; $script:warningUntil=0
                } else {
                    $failures++
                    if (-not $failureStart) { $failureStart = $now }
                    # Only a fresh exact AVR identity response supports AVR-side inference.
                    $identity = Get-AvrIdentity -AvrHost $AvrHost -ExpectedFingerprint $deviceFingerprint
                    $networkEvidence = Get-AvrNetworkEvidence $AvrHost
                }
                $nextVerify = $now + $(if (($verification.Valid -and $fresh) -or $verification.Standby) { [math]::Max(30,$VerificationSeconds) } else { 15 })
                Write-WatchdogEvent 'IndependentVerification' $verification
            }
            $observation = Read-AvrJson (Join-Path $Root 'avr_collector_observation.json')
            $fresh = Get-AvrCollectorFresh $observation $now
            $canonical = Read-AvrFields (Join-Path $Root 'denon_status.txt')
            $decoder = Read-AvrFields (Join-Path $Root 'decoder_status.txt')
            $decoderUpdated = [datetime]::MinValue
            $decoderFresh = [datetime]::TryParse([string]$decoder['Updated'],[ref]$decoderUpdated) -and
                ((Get-Date)-$decoderUpdated).TotalSeconds -le 45 -and $decoderUpdated -le (Get-Date).AddSeconds(2) -and
                -not [string]::IsNullOrWhiteSpace([string]$decoder['InputSignal'])
            if ($decoderFresh) { $decoderRestartAttempted=$false }
            elseif (-not $decoderRestartAttempted -and $now-$lastDecoderRestart -ge 600 -and $cycle -ge 15) {
                # The decoder's heartbeat can advance on failures. Try one targeted
                # restart per outage; continued endpoint failure never restarts TCP,
                # artwork, Box1, Rainmeter, or recommends RESET AVR by itself.
                if (-not $DisableRecovery) {
                    foreach($process in @(Get-TelemetryScriptProcesses -ScriptPath (Join-Path $Root 'DecoderCollector.ps1'))) {
                        [void](Stop-TelemetryScriptProcess -Process $process)
                    }
                }
                $decoderRestartAttempted=$true; $lastDecoderRestart=$now
                Write-WatchdogEvent 'DecoderRecoveryAttempt' @{Fact='No fresh valid decoder sample';Action='Targeted decoder restart via manager';Inference='Endpoint or decoder failure; not evidence of TCP control failure'}
            }
            $mismatches = @()
            if ($fresh) {
                foreach ($key in @('Source','Mode','Volume')) {
                    $value = $canonical[$key] -replace '\s+dB$', ''
                    if ($value -ne [string]$observation.Values.$key) { $mismatches += "Canonical:$key" }
                }
            }
            # Compare snapshots only within a short window; a user changing input
            # after verification is not a fault. Re-query before any escalation.
            if ($verification -and $verification.Valid -and $now - $lastVerify -le 4 -and $fresh) {
                foreach ($key in @('Power','Source','Mode','Volume')) {
                    if ([string]$verification.Values[$key] -ne [string]$observation.Values.$key) { $mismatches += "Collector:$key" }
                }
            }
            if ($now - $lastVerify -le 4 -and $verification -and $verification.Valid) {
                $script:pendingIndependentMismatch = @($mismatches | Where-Object { $_ -like 'Collector:*' })
            }
            elseif ($script:pendingIndependentMismatch.Count -gt 0) {
                $mismatches += $script:pendingIndependentMismatch
            }
            $standbyKnown = $verification -and $verification.Standby -and $now - $verification.Epoch -lt 120
            $fault = (-not $fresh -or $mismatches.Count -gt 0) -and -not $standbyKnown
            if ($fault) {
                if (-not $faultSince) { $faultSince = $now }
                $nextVerify = [math]::Min($nextVerify, $now + 15)
                if ($now -ge $nextRecovery -and $now - $faultSince -ge 5) {
                    $actionAttempted = $false
                    if ($level -eq 0) { Request-AvrRecovery 'Reconcile'; $lastRecovery = 'Read-only reconciliation'; $level = 1; $actionAttempted=$true }
                    elseif ($level -eq 1) { Request-AvrRecovery 'Reconnect'; $lastRecovery = 'Collector reconnect'; $reconnectAttempted = $true; $level = 2; $actionAttempted=$true }
                    elseif ($level -eq 2 -and $now - $lastRestart -ge 600) {
                        if (-not $DisableRecovery) {
                            foreach ($process in @(Get-TelemetryScriptProcesses -ScriptPath $collector)) { [void](Stop-TelemetryScriptProcess -Process $process) }
                        }
                        # Manager owns replacement, preventing duplicate starts.
                        $lastRecovery = 'Collector restart requested via manager'; $restartAttempted = $true
                        $lastRestart = $now; $level = 3
                        $actionAttempted=$true
                    }
                    $nextRecovery = $now + 30
                    if ($actionAttempted) { Write-WatchdogEvent 'RecoveryAttempt' @{Action=$lastRecovery;Level=$level;Fact='Freshness or snapshot mismatch';Mismatches=$mismatches} }
                }
            } elseif ($level -gt 0 -or $faultSince -gt 0) {
                $recoveredAt = $now; $level = 0; $faultSince = 0
                $reconnectAttempted = $false; $restartAttempted = $false
                Write-WatchdogEvent 'RecoveryVerified' @{Fact='Fresh critical observations and canonical agreement';LastAction=$lastRecovery}
            }
            $reset = Get-AvrResetEligible -Failures $failures -FailureSeconds ($now-$failureStart) -IdentityVerified $identity -CollectorFresh $fresh -ReconnectAttempted $reconnectAttempted -RestartAttempted $restartAttempted -BaselineVerified $baseline -PowerBeforeFailure $lastVerifiedPower
            # Retain warning only until next fresh probe; clear immediately on success.
            if ($reset) { $script:warningUntil = $now + 20 }
            if ($verification -and $verification.Valid) { $script:warningUntil = 0 }
            $reset = $script:warningUntil -gt $now
            $trusted = $fresh -and $mismatches.Count -eq 0 -and $lastVerify -gt 0 -and $now-$lastVerify -lt 120 -and -not $reset
            $channelsFresh = $fresh -and $observation.Observed.Channels -and $now-[double]$observation.Observed.Channels -lt 15
            $class = if ($reset) {'AvrControlUnresponsive'} elseif ($standbyKnown) {'Standby'} elseif (-not $fresh) {'CollectorUnverified'} elseif ($mismatches.Count) {'StateMismatch'} elseif (-not $trusted) {'IndependentVerificationUnavailable'} else {'Healthy'}
            $ack = Read-AvrFields (Join-Path $Root 'avr_presentation_ack.txt')
            $presentation = 'Unobservable'
            if ($ack.Session -eq $session) {
                $presentation = if ($now - [double]$ack.Epoch -lt 8) {'Updating'} else {'Stalled'}
                if ($presentation -eq 'Updating' -and $trusted) {
                    foreach ($key in @('Source','Mode','Volume')) {
                        if (($ack[$key] -replace '\s+dB$', '') -ne [string]$observation.Values.$key) { $presentation = 'Mismatch' }
                    }
                }
            } elseif ($now - $lastVerify -lt 120 -and $lastVerify -gt 0) { $presentation = 'MissingAcknowledgment' }
            if ($trusted -and $presentation -in @('Stalled','Mismatch','MissingAcknowledgment') -and $now - $lastPresentationRepair -ge 120 -and $presentationAttempts -lt 2) {
                if (-not $DisableRecovery) { Invoke-AvrPresentationRepair -Refresh:($presentationAttempts -eq 1) }
                $lastPresentationRepair=$now; $presentationAttempts++
                Write-WatchdogEvent 'PresentationRecoveryAttempt' @{Action=$(if($presentationAttempts -eq 1){'Targeted update'}else{'Targeted skin refresh'});Fact=$presentation}
            }
            if ($presentation -eq 'Updating') { $presentationAttempts = 0 }
            $health = @{
                Epoch=$now;Session=$session;PID=$PID;Overall=$class;Trusted=$trusted;ResetAvr=$reset
                LastIndependentVerification=$lastVerify;LastComprehensiveReconciliation=$lastComprehensive
                BaselineVerified=$baseline
                LastVerifiedPower=$lastVerifiedPower
                DeviceFingerprint=$deviceFingerprint
                CollectorFresh=$fresh;Collector=$observation;StateEngine=$(if($mismatches.Count){'Mismatch'}else{'NoObservedMismatch'})
                Presentation=$presentation;Mismatches=$mismatches;Verification=$verification
                DecoderFresh=$decoderFresh;DecoderLastSample=[string]$decoder['Updated'];DecoderRestartAttempted=$decoderRestartAttempted
                ChannelsFresh=[bool]$channelsFresh;OptionalHealth=$(if($decoderFresh){'DecoderFresh'}else{'DecoderStaleOrInvalid'})
                Failures=$failures;Escalation=$level;LastAction=$lastRecovery;LastSuccessfulRecovery=$recoveredAt
                IdentityVerifiedThisCycle=$identity
                NetworkEvidence=$networkEvidence
                ControlService=$(if($verification.Valid){'FreshReplies'}elseif($verification.TcpConnected){'TcpAcceptedButRepliesInvalidOrMissing'}else{'FreshTcpFailed'})
                FailureDomainInference=$(if($verification.Valid -and -not $fresh){'CollectorOrExistingSession'}elseif($identity){'IdentifiedAvrRespondsOnSeparateService'}elseif($networkEvidence -and -not $networkEvidence.LocalInterfaceUp){'LocalNetworkingUnavailable'}elseif($networkEvidence -and $networkEvidence.AvrIcmp){'AddressRespondsButControlUnverified'}elseif($networkEvidence -and $networkEvidence.GatewayIcmp){'LANPeerRespondsAvrAddressUnverified'}elseif($networkEvidence){'LANOrAvrFailureAmbiguous'}else{'NoControlFailureObserved'})
                ResetReason=$(if($reset){'Inference: repeated missing fresh TCP replies despite fresh exact-model HEOS identity; reconnect and collector restart failed'}else{''})
                Limitation='Fresh network replies verify reported AVR state, not physical front-panel correctness; no independent physical sensor.'
            }
            Write-AvrJson $statusPath $health
            $display = "Epoch=$now`nSession=$session`nTrusted=$([int]$trusted)`nResetAvr=$([int]$reset)`nChannelsFresh=$([int][bool]$channelsFresh)`n"
            Write-AvrText $displayPath $display
            if ($class -ne $lastClass -or $now-$lastLog -ge 300) { Write-WatchdogEvent 'Health' $health; $lastClass=$class; $lastLog=$now }
        } catch { Write-WatchdogEvent 'WatchdogCycleError' @{Fact=$_.Exception.Message} }
        if ($MaximumCycles -le 0 -or $cycle -lt $MaximumCycles) { Start-Sleep -Seconds 2 }
    }
} finally { try {$mutex.ReleaseMutex()} catch {}; $mutex.Dispose() }
