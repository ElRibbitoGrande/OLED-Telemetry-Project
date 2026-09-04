[CmdletBinding()]
param()

# Reference: Rainmeter 4.5.26 PluginAudioLevel.cpp. The reference path applies
# its asymmetric power envelope per audio sample. The legacy Lua implementation
# remains the 32 ms mathematical reference; the collector now applies that same
# time-domain response to every approximately 10 ms Box 1 RMS report.
$ErrorActionPreference = 'Stop'

$SampleRate = 48000
$UpdateMs = 32
$AttackMs = 85
$DecayMs = 520
$Gain = 2.7
$Tolerance = 0.00002

function Limit-UnitValue {
    param([Parameter(Mandatory)][double]$Value)

    return [Math]::Max(0.0, [Math]::Min(1.0, $Value))
}

function New-ResponseState {
    return [pscustomobject]@{ Power = [double]0.0 }
}

function Get-AudioLevelReferenceValue {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][double]$Target,
        [Parameter(Mandatory)][int]$SampleRate,
        [Parameter(Mandatory)][int]$UpdateMs,
        [Parameter(Mandatory)][int]$AttackMs,
        [Parameter(Mandatory)][int]$DecayMs,
        [Parameter(Mandatory)][double]$Gain
    )

    $sampleCountExact = $SampleRate * $UpdateMs / 1000.0
    $sampleCount = [int][Math]::Round($sampleCountExact)
    if ([Math]::Abs($sampleCountExact - $sampleCount) -gt 0.000000001) {
        throw 'The reference interval must contain a whole number of audio samples.'
    }

    $targetPower = [single]($Target * $Target)
    $power = [single]$State.Power

    for ($sample = 0; $sample -lt $sampleCount; $sample++) {
        $responseMs = $AttackMs
        if ($targetPower -lt $power) {
            $responseMs = $DecayMs
        }

        $coefficient = [single]0.0
        if ($responseMs -gt 0) {
            $coefficient = [single][Math]::Exp(
                [Math]::Log10(0.01) / ($SampleRate * $responseMs * 0.001)
            )
        }

        $power = [single]($targetPower + $coefficient * ($power - $targetPower))
    }

    $State.Power = [double]$power
    return Limit-UnitValue -Value ([Math]::Sqrt([Math]::Max(0.0, $State.Power)) * $Gain)
}

function Get-Box1EquivalentValue {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][double]$Target,
        [Parameter(Mandatory)][int]$UpdateMs,
        [Parameter(Mandatory)][int]$AttackMs,
        [Parameter(Mandatory)][int]$DecayMs,
        [Parameter(Mandatory)][double]$Gain
    )

    $target = Limit-UnitValue -Value $Target
    $targetPower = $target * $target
    $responseMs = $AttackMs
    if ($targetPower -lt $State.Power) {
        $responseMs = $DecayMs
    }

    $coefficient = 0.0
    if ($responseMs -gt 0) {
        $coefficient = [Math]::Exp([Math]::Log10(0.01) * $UpdateMs / $responseMs)
    }

    $State.Power = $targetPower + $coefficient * ($State.Power - $targetPower)
    return Limit-UnitValue -Value ([Math]::Sqrt([Math]::Max(0.0, $State.Power)) * $Gain)
}

function Test-Sequence {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][double[]]$Targets
    )

    $referenceState = New-ResponseState
    $box1State = New-ResponseState
    $maximumError = 0.0

    for ($index = 0; $index -lt $Targets.Count; $index++) {
        $reference = Get-AudioLevelReferenceValue `
            -State $referenceState `
            -Target $Targets[$index] `
            -SampleRate $SampleRate `
            -UpdateMs $UpdateMs `
            -AttackMs $AttackMs `
            -DecayMs $DecayMs `
            -Gain $Gain
        $box1 = Get-Box1EquivalentValue `
            -State $box1State `
            -Target $Targets[$index] `
            -UpdateMs $UpdateMs `
            -AttackMs $AttackMs `
            -DecayMs $DecayMs `
            -Gain $Gain

        $error = [Math]::Abs($reference - $box1)
        $maximumError = [Math]::Max($maximumError, $error)
        if ($error -gt $Tolerance) {
            throw "$Name failed at frame $index. Reference=$reference Box1=$box1 Error=$error"
        }
    }

    [pscustomobject]@{
        Sequence = $Name
        Frames = $Targets.Count
        MaximumError = $maximumError
    }
}

$sequences = [ordered]@{
    StepUp = [double[]](0, 0, 0, 0.65, 0.65, 0.65, 0.65, 0.65, 0.65)
    StepDown = [double[]](0.8, 0.8, 0.8, 0.8, 0.2, 0.2, 0.2, 0.2, 0.2)
    ShortPulse = [double[]](0, 0, 0.9, 0, 0, 0, 0)
    RepeatedPulses = [double[]](0, 0.75, 0, 0.75, 0, 0.75, 0, 0)
    AlternatingRiseFall = [double[]](0.1, 0.8, 0.25, 0.7, 0.15, 0.6, 0.05, 0.5)
    IncompleteDirections = [double[]](0, 0.25, 0.55, 0.85, 0.4, 0.7, 0.3, 0.65, 0.1)
}

$results = foreach ($entry in $sequences.GetEnumerator()) {
    Test-Sequence -Name $entry.Key -Targets $entry.Value
}

foreach ($target in [double[]](0, 0.1, 0.2, 0.5, 1.0)) {
    $state = New-ResponseState
    $actual = Get-Box1EquivalentValue `
        -State $state `
        -Target $target `
        -UpdateMs $UpdateMs `
        -AttackMs 0 `
        -DecayMs 0 `
        -Gain $Gain
    $expected = Limit-UnitValue -Value ($target * $Gain)
    if ([Math]::Abs($actual - $expected) -gt 0.000000000001) {
        throw "Gain/clamp validation failed for target $target. Expected=$expected Actual=$actual"
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$luaPath = Join-Path $repositoryRoot 'src\@Resources\VU\Box1VUResponse.lua'
$meterResponsePath = Join-Path $repositoryRoot 'src\@Resources\VU\MeterResponse.inc'
$signalAcquisitionPath = Join-Path $repositoryRoot 'src\@Resources\VU\SignalAcquisition.inc'
$responseVariablesPath = Join-Path $repositoryRoot 'src\@Resources\MeterStyles\AnalogFloating\Response.inc'
$dashboardStatePath = Join-Path $repositoryRoot 'src\@Resources\Includes\DashboardState.inc'
$dashboardTelemetryPath = Join-Path $repositoryRoot 'src\@Resources\Includes\DashboardTelemetry.inc'
$collectorPath = Join-Path $repositoryRoot 'src\Box1Collector.ps1'

$lua = Get-Content -Raw -LiteralPath $luaPath
$meterResponse = Get-Content -Raw -LiteralPath $meterResponsePath
$signalAcquisition = Get-Content -Raw -LiteralPath $signalAcquisitionPath
$responseVariables = Get-Content -Raw -LiteralPath $responseVariablesPath
$dashboardState = Get-Content -Raw -LiteralPath $dashboardStatePath
$dashboardTelemetry = Get-Content -Raw -LiteralPath $dashboardTelemetryPath
$collector = Get-Content -Raw -LiteralPath $collectorPath

$requiredLuaPatterns = @(
    'local targetPower = target \* target',
    'if targetPower < rmsPower then',
    'math\.exp\(log10OnePercent \* updateMs / responseMs\)',
    'rmsPower = targetPower \+ coefficient \* \(rmsPower - targetPower\)',
    'math\.sqrt\(math\.max\(0, rmsPower\)\) \* gain'
)
foreach ($pattern in $requiredLuaPatterns) {
    if ($lua -notmatch $pattern) {
        throw "Lua implementation validation failed. Missing pattern: $pattern"
    }
}

if ($lua -match 'AverageSize|peak|vu|hold|Start-Sleep|sleep\(') {
    throw 'Lua implementation contains an unexpected smoothing, peak, hold, or pacing mechanism.'
}
if ($meterResponse -match 'AverageSize') {
    throw 'MeterResponse.inc contains unexpected AverageSize smoothing.'
}
if ($meterResponse -notmatch 'DashboardRawBox1RmsEnvelopeLeft \* #DashboardVUGain#' -or
    $meterResponse -notmatch 'DashboardRawBox1RmsEnvelopeRight \* #DashboardVUGain#' -or
    $meterResponse -match 'ScriptFile=#@#VU\\Box1VUResponse\.lua') {
    throw 'MeterResponse.inc is not using the collector-side Box 1 RMS envelope directly.'
}
if ($dashboardTelemetry -notmatch 'Measure=Registry' -or
    ([regex]::Matches($dashboardTelemetry, 'RegHKey=HKEY_LOCAL_MACHINE').Count -ne 10) -or
    ([regex]::Matches($dashboardTelemetry, 'RegKey=Software\\OLED-Telemetry-Project\\Box1Runtime').Count -ne 10) -or
    $dashboardTelemetry -notmatch 'RegValue=LeftRmsDb' -or
    $dashboardTelemetry -notmatch 'RegValue=RightRmsDb' -or
    $dashboardTelemetry -notmatch 'RegValue=LeftRmsEnvelope' -or
    $dashboardTelemetry -notmatch 'RegValue=RightRmsEnvelope' -or
    $dashboardTelemetry -match '\[DashboardBox1StateFile\]') {
    throw 'DashboardTelemetry.inc is not using the synchronous Box 1 registry transport.'
}
if ($dashboardState -notmatch 'Formula=Clamp\(10 \*\* \(DashboardRawBox1LeftRmsDb / 20\), 0, 1\)' -or
    $dashboardState -notmatch 'Formula=Clamp\(10 \*\* \(DashboardRawBox1RightRmsDb / 20\), 0, 1\)') {
    throw 'DashboardState.inc is not converting Box 1 RMS dBFS to linear amplitude.'
}
if ($signalAcquisition -notmatch 'RMSAttack=#DashboardVUAttack#' -or
    $signalAcquisition -notmatch 'RMSDecay=#DashboardVUDecay#' -or
    $signalAcquisition -notmatch 'RMSGain=#DashboardVUGain#') {
    throw 'The Windows AudioLevel response configuration has changed unexpectedly.'
}
if ($responseVariables -notmatch 'DashboardVUGain=2\.7' -or
    $responseVariables -notmatch 'DashboardVUAttack=85' -or
    $responseVariables -notmatch 'DashboardVUDecay=520') {
    throw 'The shared VU response values are not 2.7 / 85 ms / 520 ms.'
}
if ($collector -notmatch '\$RmsAttackMilliseconds = 85\.0' -or
    $collector -notmatch '\$RuntimeRegistrySubKey = ''Software\\OLED-Telemetry-Project\\Box1Runtime''' -or
    $collector -notmatch '\[Box1Collector\.NativeMethods\]::HKEY_LOCAL_MACHINE' -or
    $collector -notmatch '(?s)RegCreateKeyExW\(.+?\[uint32\]0,.+?\[uint32\]0,.+?\[IntPtr\]::Zero' -or
    $collector -notmatch '\$RmsDecayMilliseconds = 520\.0' -or
    $collector -notmatch '\[Math\]::Log10\(0\.01\) \* \$ElapsedMilliseconds / \$responseMilliseconds' -or
    $collector -notmatch 'TargetLevel \$leftRmsLevel' -or
    $collector -notmatch 'TargetLevel \$rightRmsLevel' -or
    $collector -notmatch 'LeftRmsEnvelope = \[Math\]::Min' -or
    $collector -notmatch 'RightRmsEnvelope = \[Math\]::Min') {
    throw 'Box1Collector.ps1 is not applying the AudioLevel-equivalent RMS response.'
}
if ($collector -match 'Start-Sleep.+Rms|AverageSize|transient hold|rolling max') {
    throw 'The Box 1 RMS response contains an unexpected pacing or transient mechanism.'
}

$results | Format-Table -AutoSize
'Gain/clamp validation: PASS'
'Source-path, registry transport, and no-additional-smoothing validation: PASS'
