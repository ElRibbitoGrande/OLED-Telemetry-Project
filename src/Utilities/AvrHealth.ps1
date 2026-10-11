# Shared bounded IO and pure health decisions. No AVR mutation commands.
function Get-AvrEpoch { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Read-AvrJson([string]$Path) {
    try { Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
}
function Write-AvrJson([string]$Path, $Value) {
    Write-AvrText $Path ($Value | ConvertTo-Json -Depth 10)
}
function Write-AvrText([string]$Path, [string]$Content) {
    $temporary = "$Path.$PID.tmp"
    try {
        for($attempt=1;$attempt -le 3;$attempt++) {
            try {
                [IO.File]::WriteAllText($temporary, $Content, [Text.UTF8Encoding]::new($false))
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [Management.Automation.Language.NullString]::Value) }
                else { [IO.File]::Move($temporary, $Path) }
                return
            } catch { if($attempt -eq 3){throw};Start-Sleep -Milliseconds 50 }
        }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Read-AvrFields([string]$Path) {
    $fields = @{}
    try {
        foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
            if ($line -match '^([^=]+)=(.*)$') { $fields[$Matches[1]] = $Matches[2] }
        }
    } catch {}
    return $fields
}
function Import-AvrValueParsers([string]$CollectorPath) {
    # Reuse only pure formatting functions, never the collector's stored values.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($CollectorPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Collector parser validation failed' }
    foreach ($name in @('Normalize-Source','Format-ListeningMode','Convert-DenonVolume')) {
        $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
        . ([scriptblock]::Create(($node.Extent.Text -replace ('^function ' + [regex]::Escape($name)), ('function script:' + $name))))
    }
}
function Get-AvrVerification {
    param([string]$AvrHost, [int]$Port = 23, [int]$TimeoutMilliseconds = 2500, [switch]$Comprehensive)
    $result = @{ Epoch=Get-AvrEpoch; TcpConnected=$false; Valid=$false; Values=@{}; Error=''; ChannelsComplete=$false }
    $client = [Net.Sockets.TcpClient]::new()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $task = $client.ConnectAsync($AvrHost, $Port)
        if (-not $task.Wait([math]::Min(1500, $TimeoutMilliseconds))) { throw 'TCP connect timeout' }
        $result.TcpConnected = $true
        $stream = $client.GetStream(); $stream.WriteTimeout = 500
        $commands = @('PW?','SI?','MV?','MS?')
        if ($Comprehensive) { $commands += @('CV?','MSQUICK ?') }
        foreach ($command in $commands) {
            $bytes = [Text.Encoding]::ASCII.GetBytes($command + "`r")
            $stream.Write($bytes, 0, $bytes.Length)
            Start-Sleep -Milliseconds 60
        }
        $pending = ''; $buffer = New-Object byte[] 4096
        while ($clock.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
            if ($stream.DataAvailable) {
                $count = $stream.Read($buffer, 0, $buffer.Length)
                if ($count -eq 0) { break }
                $pending += [Text.Encoding]::ASCII.GetString($buffer, 0, $count)
                while ($pending.Contains("`r")) {
                    $end = $pending.IndexOf("`r")
                    $line = $pending.Substring(0, $end).Trim()
                    $pending = $pending.Substring($end + 1)
                    if ($line -match '^PW(ON|STANDBY)$') { $result.Values.Power = $Matches[1] }
                    elseif ($line -match '^SI(.+)$') { $result.Values.Source = Normalize-Source $Matches[1] }
                    elseif ($line -match '^MV\d{2,3}$') { $result.Values.Volume = Convert-DenonVolume $line }
                    elseif ($line -match '^MS(?!QUICK)(.+)$') { $result.Values.Mode = Format-ListeningMode $Matches[1] }
                    elseif ($line -eq 'CVEND') { $result.ChannelsComplete = $true }
                    elseif ($line -match '^MSQUICK\s*([1-4])$') { $result.Values.QuickSelect = $Matches[1] }
                }
                if ($pending.Length -gt 8192) { throw 'Invalid oversized response' }
            }
            $result.Valid = @('Power','Source','Volume','Mode' | Where-Object {
                [string]::IsNullOrWhiteSpace([string]$result.Values[$_])
            }).Count -eq 0
            if ($result.Valid -and (-not $Comprehensive -or $result.ChannelsComplete)) { break }
            Start-Sleep -Milliseconds 20
        }
        if (-not $result.Valid) { $result.Error = 'Critical query replies missing or invalid' }
    } catch { $result.Error = $_.Exception.Message }
    finally { $client.Dispose(); $result.ElapsedMilliseconds = $clock.ElapsedMilliseconds }
    $result.Epoch = Get-AvrEpoch
    $result.Standby = $result.Values.Power -eq 'STANDBY'
    return $result
}
function Get-AvrIdentity([string]$AvrHost) {
    # HEOS device description is a separate service; identify the exact model.
    # ICMP or an open port alone must never enable RESET AVR.
    try {
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        $raw = & $curl --silent --show-error --noproxy '*' --connect-timeout 1 --max-time 2 --max-filesize 65536 "http://${AvrHost}:60006/upnp/desc/aios_device/aios_device.xml" 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        [xml]$xml = $raw -join "`n"
        return ($xml.SelectSingleNode("//*[local-name()='device']/*[local-name()='modelName']").InnerText -eq 'Denon AVR-X3700H')
    } catch { return $false }
}
function Get-AvrCollectorFresh($Observation, [double]$Now) {
    if (-not $Observation -or $Now - [double]$Observation.Epoch -gt 8 -or [double]$Observation.Epoch -gt $Now + 2) { return $false }
    foreach ($key in @('Power','Source','Volume','Mode')) {
        if (-not $Observation.Observed.$key -or $Now - [double]$Observation.Observed.$key -gt 15 -or
            [double]$Observation.Observed.$key -gt $Now + 2 -or [string]::IsNullOrWhiteSpace([string]$Observation.Values.$key)) { return $false }
    }
    return $true
}
function Get-AvrResetEligible {
    param([int]$Failures, [double]$FailureSeconds, [bool]$IdentityVerified, [bool]$CollectorFresh, [bool]$ReconnectAttempted, [bool]$RestartAttempted, [bool]$BaselineVerified)
    return ($Failures -ge 6 -and $FailureSeconds -ge 180 -and $IdentityVerified -and
        -not $CollectorFresh -and $ReconnectAttempted -and $RestartAttempted -and $BaselineVerified)
}
