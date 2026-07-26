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

function Get-QuickSelect {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Success = $false
            Value = $null
            Message = "MISSING: $Path"
        }
    }

    try {
        $line = Get-Content -LiteralPath $Path -ErrorAction Stop |
            Where-Object { $_ -match "^QuickSelect=(.*)$" } |
            Select-Object -First 1

        if ($null -eq $line -or $line -notmatch "^QuickSelect=(.*)$") {
            throw "QuickSelect entry was not found."
        }

        $value = 0
        if (-not [int]::TryParse($Matches[1].Trim(), [ref]$value)) {
            throw "QuickSelect value '$($Matches[1].Trim())' is not an integer."
        }

        return [pscustomobject]@{
            Success = $true
            Value = $value
            Message = "Quick Select: $value"
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Value = $null
            Message = "ERROR: $($_.Exception.Message)"
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

Write-Output "OLED Telemetry Validation"
Write-Output ("Checked: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Write-Output ("Live:    {0}" -f $LiveRoot)
Write-Output ("Repo:    {0}" -f $RepositoryRoot)

Write-Section "Quick Select"
$quickSelectResult = Get-QuickSelect -Path (Join-Path $LiveRoot "denon_status.txt")
Write-Output $quickSelectResult.Message
if (-not $quickSelectResult.Success) {
    Set-OverallSeverity "FAILED"
}

$appleExpected = 0
$wiimExpected = 0
if ($quickSelectResult.Success) {
    if ($quickSelectResult.Value -in @(1, 2)) {
        $appleExpected = 1
        Write-Output "Expected metadata collector: Apple Music"
    }
    elseif ($quickSelectResult.Value -in @(3, 4)) {
        $wiimExpected = 1
        Write-Output "Expected metadata collector: WiiM"
    }
    else {
        Write-Output "Expected metadata collector: Neither"
    }
}
else {
    Write-Output "Expected metadata collector: UNKNOWN"
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

    if (-not $quickSelectResult.Success) {
        Set-OverallSeverity "FAILED"
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
    "NowPlaying\NowPlayingRouter.ps1"
    "NowPlaying\AppleMusicCollector.ps1"
    "NowPlaying\WiiM-NowPlaying-Bridge.ps1"
)

foreach ($relativePath in $hashPaths) {
    Write-HashComparison -RelativePath $relativePath
}

Write-Section "Overall Result"
$overallResult = switch ($script:OverallSeverity) {
    0 { "HEALTHY" }
    1 { "WARNING" }
    default { "FAILED" }
}
Write-Output $overallResult
