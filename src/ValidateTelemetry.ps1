$LiveRoot = "C:\RainmeterDenon"
$RepositoryRoot = $PSScriptRoot

$DenonHeartbeatThresholdSeconds = 12
$DecoderHeartbeatThresholdSeconds = 30
$RouterHeartbeatThresholdSeconds = 12

$script:OverallSeverity = 0

function Set-OverallSeverity {
    param([ValidateSet("WARNING", "FAILED")][string]$Severity)

    $value = if ($Severity -eq "FAILED") { 2 } else { 1 }
    if ($value -gt $script:OverallSeverity) {
        $script:OverallSeverity = $value
    }
}

function Write-Section {
    param([string]$Title)

    Write-Output ""
    Write-Output $Title
    Write-Output ("-" * $Title.Length)
}

function Get-DenonState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Success = $false
            Values = @{}
            Message = "MISSING: $Path"
        }
    }

    try {
        $values = @{}
        foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
            if ($line -match "^([^=]+)=(.*)$") {
                $values[$Matches[1]] = $Matches[2].Trim()
            }
        }

        foreach ($requiredKey in @("Source", "DisplayMode", "LevelSource")) {
            if (-not $values.ContainsKey($requiredKey) -or
                [string]::IsNullOrWhiteSpace([string]$values[$requiredKey])) {

                throw "$requiredKey entry was not found or was empty."
            }
        }

        return [pscustomobject]@{
            Success = $true
            Values = $values
            Message = ""
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Values = @{}
            Message = "ERROR: $($_.Exception.Message)"
        }
    }
}

function Get-ExpectedDisplayRouting {
    param([hashtable]$State)

    $source = ([string]$State.Source).Trim().ToUpperInvariant()
    $formatText = "{0} {1}" -f [string]$State.InputSignal, [string]$State.Mode
    $formatDisplayMode = if ($formatText -match "DTS:X|NEURAL:X") {
        "DTSX_LOGO"
    }
    elseif ([string]$State.VisualMode -eq "ATMOS" -or $formatText -match "ATMOS") {
        "ATMOS_LOGO"
    }
    else {
        "VU"
    }

    switch ($source) {
        "HTPC" {
            return [pscustomobject]@{
                Collector = "Apple"
                AppleExpected = 1
                WiiMExpected = 0
                DisplayMode = $formatDisplayMode
                LevelSource = if ($formatDisplayMode -eq "VU") { "PC_AUDIO" } else { "NONE" }
            }
        }
        "LYR+" {
            return [pscustomobject]@{
                Collector = "WiiM"
                AppleExpected = 0
                WiiMExpected = 1
                DisplayMode = "VU"
                LevelSource = "NONE"
            }
        }
        "XBOX" {
            return [pscustomobject]@{
                Collector = "None"
                AppleExpected = 0
                WiiMExpected = 0
                DisplayMode = "XBOX_LOGO"
                LevelSource = "NONE"
            }
        }
        "PS5" {
            return [pscustomobject]@{
                Collector = "None"
                AppleExpected = 0
                WiiMExpected = 0
                DisplayMode = "PS5_LOGO"
                LevelSource = "NONE"
            }
        }
        default {
            return [pscustomobject]@{
                Collector = "None"
                AppleExpected = 0
                WiiMExpected = 0
                DisplayMode = $formatDisplayMode
                LevelSource = "NONE"
            }
        }
    }
}

function Get-TelemetryProcesses {
    try {
        $processes = @(
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop
        )

        return [pscustomobject]@{
            Success = $true
            Processes = $processes
            Message = ""
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Processes = @()
            Message = $_.Exception.Message
        }
    }
}

function Get-MatchingProcesses {
    param(
        [object[]]$Processes,
        [string]$ScriptName
    )

    $escapedName = [regex]::Escape($ScriptName)
    return @(
        $Processes | Where-Object {
            $_.CommandLine -and $_.CommandLine -match $escapedName
        }
    )
}

function Write-ProcessResult {
    param(
        [string]$Name,
        [object[]]$Matches,
        [int]$ExpectedCount
    )

    $count = @($Matches).Count
    $pids = if ($count -gt 0) {
        (@($Matches | Select-Object -ExpandProperty ProcessId) -join ",")
    }
    else {
        "-"
    }

    if ($count -eq $ExpectedCount) {
        $status = "OK"
    }
    elseif ($count -gt 1) {
        $status = "DUPLICATE"
        Set-OverallSeverity "FAILED"
    }
    elseif ($ExpectedCount -eq 1 -and $count -eq 0) {
        $status = "MISSING"
        Set-OverallSeverity "FAILED"
    }
    else {
        $status = "UNEXPECTED"
        Set-OverallSeverity "FAILED"
    }

    Write-Output ("{0,-32} Count={1,-2} PID={2,-14} {3}" -f $Name, $count, $pids, $status)
}

function Write-FileFreshness {
    param(
        [string]$Label,
        [string]$Path,
        [Nullable[double]]$StaleThresholdSeconds
    )

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Output ("{0,-28} MISSING  {1}" -f $Label, $Path)
            Set-OverallSeverity "FAILED"
            return
        }

        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $age = [math]::Max(0, ((Get-Date) - $item.LastWriteTime).TotalSeconds)
        $status = "OK"

        if ($null -ne $StaleThresholdSeconds -and $age -gt [double]$StaleThresholdSeconds) {
            $status = "STALE (threshold {0:N0}s)" -f [double]$StaleThresholdSeconds
            Set-OverallSeverity "FAILED"
        }

        Write-Output (
            "{0,-28} Exists=Yes  LastWrite={1}  Age={2,7:N1}s  {3}" -f
            $Label,
            $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss.fff zzz"),
            $age,
            $status
        )
    }
    catch {
        Write-Output ("{0,-28} ERROR: {1}" -f $Label, $_.Exception.Message)
        Set-OverallSeverity "FAILED"
    }
}

function Write-HashComparison {
    param(
        [string]$RelativePath
    )

    $repositoryPath = Join-Path $RepositoryRoot $RelativePath
    $livePath = Join-Path $LiveRoot $RelativePath

    try {
        if (-not (Test-Path -LiteralPath $repositoryPath -PathType Leaf)) {
            Write-Output ("{0,-48} MISSING (repository)" -f $RelativePath)
            Set-OverallSeverity "FAILED"
            return
        }

        if (-not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
            Write-Output ("{0,-48} MISSING (live)" -f $RelativePath)
            Set-OverallSeverity "FAILED"
            return
        }

        $repositoryHash = (Get-FileHash -LiteralPath $repositoryPath -Algorithm SHA256 -ErrorAction Stop).Hash
        $liveHash = (Get-FileHash -LiteralPath $livePath -Algorithm SHA256 -ErrorAction Stop).Hash

        if ($repositoryHash -eq $liveHash) {
            $status = "MATCH"
        }
        else {
            $status = "DIFFERENT"
            Set-OverallSeverity "WARNING"
        }

        Write-Output ("{0,-48} {1}" -f $RelativePath, $status)
    }
    catch {
        Write-Output ("{0,-48} ERROR: {1}" -f $RelativePath, $_.Exception.Message)
        Set-OverallSeverity "FAILED"
    }
}

function Write-OptionalConsoleImage {
    param(
        [string]$Label,
        [string]$Path
    )

    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Write-Output ("{0,-12} PRESENT  {1}" -f $Label, $Path)
        }
        else {
            Write-Output ("{0,-12} MISSING  {1}  (WARNING)" -f $Label, $Path)
            Set-OverallSeverity "WARNING"
        }
    }
    catch {
        Write-Output ("{0,-12} ERROR: {1}  (WARNING)" -f $Label, $_.Exception.Message)
        Set-OverallSeverity "WARNING"
    }
}

Write-Output "OLED Telemetry Validation"
Write-Output ("Checked: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Write-Output ("Live:    {0}" -f $LiveRoot)
Write-Output ("Repo:    {0}" -f $RepositoryRoot)

Write-Section "Display Routing"
$denonStateResult = Get-DenonState -Path (Join-Path $LiveRoot "denon_status.txt")
$appleExpected = 0
$wiimExpected = 0

if (-not $denonStateResult.Success) {
    Write-Output $denonStateResult.Message
    Write-Output "Source:             UNKNOWN"
    Write-Output "DisplayMode:        UNKNOWN"
    Write-Output "LevelSource:        UNKNOWN"
    Write-Output "Expected collector: UNKNOWN"
    Set-OverallSeverity "FAILED"
}
else {
    $denonState = $denonStateResult.Values
    $expectedRouting = Get-ExpectedDisplayRouting -State $denonState
    $appleExpected = $expectedRouting.AppleExpected
    $wiimExpected = $expectedRouting.WiiMExpected

    Write-Output ("Source:             {0}" -f $denonState.Source)
    Write-Output ("DisplayMode:        {0}" -f $denonState.DisplayMode)
    Write-Output ("LevelSource:        {0}" -f $denonState.LevelSource)
    Write-Output ("Expected collector: {0}" -f $expectedRouting.Collector)

    if ([string]$denonState.DisplayMode -ne $expectedRouting.DisplayMode) {
        Write-Output ("FAILED: DisplayMode expected {0}." -f $expectedRouting.DisplayMode)
        Set-OverallSeverity "FAILED"
    }

    if ([string]$denonState.LevelSource -notin @("PC_AUDIO", "ANALOG_ADC", "NONE")) {
        Write-Output "FAILED: LevelSource is not a recognized value."
        Set-OverallSeverity "FAILED"
    }

    if ([string]$denonState.LevelSource -ne $expectedRouting.LevelSource) {
        Write-Output ("FAILED: LevelSource expected {0}." -f $expectedRouting.LevelSource)
        Set-OverallSeverity "FAILED"
    }
}

Write-Section "Telemetry Processes"
$processResult = Get-TelemetryProcesses
if (-not $processResult.Success) {
    Write-Output ("FAILED: Could not query PowerShell processes: {0}" -f $processResult.Message)
    foreach ($name in @(
        "TelemetryManager.ps1"
        "denon_status.ps1"
        "DecoderCollector.ps1"
        "NowPlayingRouter.ps1"
        "AppleMusicCollector.ps1"
        "WiiM-NowPlaying-Bridge.ps1"
    )) {
        Write-Output ("{0,-32} Count=?  PID={1,-14} UNKNOWN" -f $name, "-")
    }
    Set-OverallSeverity "FAILED"
}
else {
    $processExpectations = @(
        [pscustomobject]@{ Name = "TelemetryManager.ps1"; Expected = 1 }
        [pscustomobject]@{ Name = "denon_status.ps1"; Expected = 1 }
        [pscustomobject]@{ Name = "DecoderCollector.ps1"; Expected = 1 }
        [pscustomobject]@{ Name = "NowPlayingRouter.ps1"; Expected = 1 }
        [pscustomobject]@{ Name = "AppleMusicCollector.ps1"; Expected = $appleExpected }
        [pscustomobject]@{ Name = "WiiM-NowPlaying-Bridge.ps1"; Expected = $wiimExpected }
    )

    foreach ($expectation in $processExpectations) {
        $matches = Get-MatchingProcesses `
            -Processes $processResult.Processes `
            -ScriptName $expectation.Name

        Write-ProcessResult `
            -Name $expectation.Name `
            -Matches $matches `
            -ExpectedCount $expectation.Expected
    }
}

Write-Section "Live File Freshness"
Write-FileFreshness `
    -Label "denon_heartbeat.txt" `
    -Path (Join-Path $LiveRoot "denon_heartbeat.txt") `
    -StaleThresholdSeconds $DenonHeartbeatThresholdSeconds

Write-FileFreshness `
    -Label "decoder_heartbeat.txt" `
    -Path (Join-Path $LiveRoot "decoder_heartbeat.txt") `
    -StaleThresholdSeconds $DecoderHeartbeatThresholdSeconds

Write-FileFreshness `
    -Label "router_heartbeat.txt" `
    -Path (Join-Path $LiveRoot "NowPlaying\router_heartbeat.txt") `
    -StaleThresholdSeconds $RouterHeartbeatThresholdSeconds

Write-FileFreshness `
    -Label "now_playing.txt" `
    -Path (Join-Path $LiveRoot "NowPlaying\now_playing.txt") `
    -StaleThresholdSeconds $null

Write-Section "Repository vs Live SHA256"
$hashPaths = @(
    "TelemetryManager.ps1"
    "denon_status.ps1"
    "DecoderCollector.ps1"
    "StopTelemetry.cmd"
    "RestartTelemetry.cmd"
    "Analog_Floating.ini"
    "NowPlaying\NowPlayingRouter.ps1"
    "NowPlaying\AppleMusicCollector.ps1"
    "NowPlaying\WiiM-NowPlaying-Bridge.ps1"
)

foreach ($relativePath in $hashPaths) {
    Write-HashComparison -RelativePath $relativePath
}

Write-Section "Optional Console Images"
$consoleImageRoot = Join-Path $LiveRoot "@Resources\Images\formats"
Write-OptionalConsoleImage `
    -Label "Xbox" `
    -Path (Join-Path $consoleImageRoot "Xbox_Logo.png")

Write-OptionalConsoleImage `
    -Label "PS5" `
    -Path (Join-Path $consoleImageRoot "PS5_Logo.png")

Write-Section "Overall Result"
$overallResult = switch ($script:OverallSeverity) {
    0 { "HEALTHY" }
    1 { "WARNING" }
    default { "FAILED" }
}
Write-Output $overallResult
