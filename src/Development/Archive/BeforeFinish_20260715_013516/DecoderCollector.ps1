$ErrorActionPreference = "Stop"

$Root = "C:\RainmeterDenon"
$OutFile = Join-Path $Root "decoder_status.txt"
$TempFile = Join-Path $Root "decoder_status.tmp"
$HeartbeatFile = Join-Path $Root "decoder_heartbeat.txt"
$ErrorFile = Join-Path $Root "decoder_status_error.txt"
$Ip = "192.168.0.128"
$Curl = "$env:SystemRoot\System32\curl.exe"

New-Item -ItemType Directory -Path $Root -Force | Out-Null

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, "Local\RainmeterDenonDecoderCollector", [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Normalize-Mode([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim().ToUpperInvariant()
    $v = $v.Replace("DOLBY AUDIO - DOLBY SURROUND", "DOLBY SURROUND")
    if ($v -match "ATMOS") { return "DOLBY ATMOS" }
    if ($v -match "DSUR") { return "DOLBY SURROUND" }
    return $v
}

function Normalize-Format([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    $v = $v.Replace("Dolby Atmos - DD+", "DD+ ATMOS")
    $v = $v.Replace("Dolby Atmos - TrueHD", "TRUEHD ATMOS")
    $v = $v.Replace("Dolby Audio - DD+", "DD+")
    $v = $v.Replace("Dolby Audio - DD", "DD")
    $v = $v.Replace("Multichannel PCM", "PCM MULTI")
    return $v.ToUpperInvariant()
}

try {
    while ($true) {
        $started = Get-Date
        $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $url = "https://$Ip`:10443/ajax/general/get_config?type=12&_=$cacheBust"
        $curlOutput = Join-Path $Root "decoder_response.xml"
        $curlError = Join-Path $Root "decoder_curl_error.txt"

        Remove-Item $curlOutput, $curlError -Force -ErrorAction SilentlyContinue

        try {
            # The Denon's HTTPS server performs TLS renegotiation and typically takes
            # about 7–8 seconds to answer. A 12-second timeout is intentional.
            & $Curl -k -sS --connect-timeout 5 --max-time 12 -o $curlOutput $url 2> $curlError
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0) {
                $stderr = if (Test-Path $curlError) { (Get-Content $curlError -Raw).Trim() } else { "" }
                throw "curl exit code $exitCode. $stderr"
            }
            if (-not (Test-Path $curlOutput)) { throw "No decoder response file was created." }

            $raw = Get-Content $curlOutput -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($raw)) { throw "Decoder response was empty." }

            [xml]$xml = $raw
            $soundModeRaw = [string]$xml.Information.Audio.SoundMode
            $inputSignalRaw = [string]$xml.Information.Audio.InputSignal
            $sampleRate = [string]$xml.Information.Audio.SampleRate

            $mode = Normalize-Mode $soundModeRaw
            $format = Normalize-Format $inputSignalRaw

            $text = @"
Mode=$mode
InputSignal=$format
SampleRate=$sampleRate
SoundModeRaw=$soundModeRaw
InputSignalRaw=$inputSignalRaw
Updated=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff")
"@
            Set-Content -LiteralPath $TempFile -Value $text -Encoding ASCII
            Move-Item -LiteralPath $TempFile -Destination $OutFile -Force
            Set-Content -LiteralPath $HeartbeatFile -Value (Get-Date -Format "o") -Encoding ASCII
            Remove-Item $ErrorFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            $message = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $_.Exception.Message
            Set-Content -LiteralPath $ErrorFile -Value $message -Encoding UTF8
            Set-Content -LiteralPath $HeartbeatFile -Value (Get-Date -Format "o") -Encoding ASCII
        }

        # Avoid hammering the Denon's unusually slow HTTPS endpoint. The request
        # itself takes most of this cycle, so typical decoder latency is 8–10 seconds.
        $elapsed = ((Get-Date) - $started).TotalMilliseconds
        $remaining = [Math]::Max(250, 8000 - $elapsed)
        Start-Sleep -Milliseconds ([int]$remaining)
    }
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}
