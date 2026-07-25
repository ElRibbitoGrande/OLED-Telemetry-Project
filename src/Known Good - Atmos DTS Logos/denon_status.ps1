$ip = "192.168.0.128"
$port = 23
$outFile = "C:\RainmeterDenon\denon_status.txt"
$lastVisualMode = ""

function Convert-DenonVolume($raw) {
    $v = ($raw -replace "MV", "").Trim()
    if ($v -match "^\d{3}$") { $absolute = [double]($v.Insert($v.Length - 1, ".")) }
    elseif ($v -match "^\d{2}$") { $absolute = [double]$v }
    else { return $v }

    $relative = $absolute - 80.0
    if ($relative -gt 0) { return "+{0:0.0}" -f $relative }
    return "{0:0.0}" -f $relative
}

function Read-MatchingLine($reader, $stream, $prefix, $timeoutMs = 1200) {
    $deadline = (Get-Date).AddMilliseconds($timeoutMs)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 40
        while ($stream.DataAvailable) {
            $line = $reader.ReadLine()
            if ($line -and $line.StartsWith($prefix)) { return $line.Trim() }
        }
    }
    return ""
}

function Get-DenonXml($url) {
    try {
        $raw = (& curl.exe -k -s $url) -join "`n"
        if ($raw -match "<\?xml") { return [xml]$raw }
    } catch {}
    return $null
}

function Map-MultEQ($v) {
    switch ($v) {
        "1" { "Reference" }
        "2" { "L/R Bypass" }
        "3" { "Flat" }
        "4" { "Off" }
        default { $v }
    }
}

function Map-OnOff($v) {
    switch ($v) {
        "1" { "On" }
        "2" { "Off" }
        default { $v }
    }
}

function Map-DynamicVolume($v) {
    switch ($v) {
        "4" { "Off" }
        default { $v }
    }
}

function Format-InputSignal($v) {
    if (-not $v) { return "" }

    $display = [string]$v
    $display = $display.Replace("Dolby Atmos - DD+", "DD+ Atmos")
    $display = $display.Replace("Dolby Atmos - TrueHD", "TrueHD Atmos")
    $display = $display.Replace("Dolby Audio - DD+", "DD+")
    $display = $display.Replace("Dolby Audio - DD", "DD")
    $display = $display.Replace("Multichannel PCM", "PCM Multi")

    return $display
}

while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($ip, $port)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.NewLine = "`r"
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($stream)

        $writer.WriteLine("MV?")
        $volRaw = Read-MatchingLine $reader $stream "MV"

        $reader.Close()
        $writer.Close()
        $client.Close()

        $volume = Convert-DenonVolume $volRaw

        $info = Get-DenonXml "https://$ip`:10443/ajax/general/get_config?type=12"
        $presetXml = Get-DenonXml "https://$ip`:10443/ajax/globals/get_config?type=10"
        $audyssey = Get-DenonXml "https://$ip`:10443/ajax/audio/get_config?type=9"

        $source = $info.Information.Zone.MainZone.Name
        if (-not $source) { $source = $info.Information.Zone.MainZone.SelectSource }

        switch ($source) {
            "CBL/SAT" { $source = "PC" }
            "SAT/CBL" { $source = "PC" }
            "DVD" { $source = "PS5" }
            "8K" { $source = "XBOX" }
        }

        $mode = $info.Information.Audio.SoundMode
        $inputSignal = $info.Information.Audio.InputSignal
        $displaySignal = Format-InputSignal $inputSignal

        $sampleRate = $info.Information.Audio.SampleRate
        $speakerPreset = $presetXml.SpeakerPreset

        $multiEQRaw = $audyssey.SelectSingleNode("//MultEQ").InnerText
        $dynamicEQRaw = $audyssey.SelectSingleNode("//DynamicEQ").InnerText
        $rloRaw = $audyssey.SelectSingleNode("//ReferenceLevelOffset").InnerText
        $dynamicVolumeRaw = $audyssey.SelectSingleNode("//DynamicVolume").InnerText

        $multiEQ = Map-MultEQ $multiEQRaw
        $dynamicEQ = Map-OnOff $dynamicEQRaw
        $rlo = "$rloRaw dB"
        $dynamicVolume = Map-DynamicVolume $dynamicVolumeRaw

        $modeClean = $mode.ToUpper()

        # Compact Denon mode names for Rainmeter display.
        # Longer strings must be replaced before shorter strings.
        $modeClean = $modeClean.Replace("DOLBY AUDIO - DOLBY SURROUND", "DOLBY SURROUND")
        $modeClean = $modeClean.Replace("DOLBY AUDIO - DD+ + DSUR", "DSUR")
        $modeClean = $modeClean.Replace("DOLBY AUDIO - DD+ + NEURAL:X", "NEURAL:X")
        $modeClean = $modeClean.Replace("DOLBY AUDIO - DD + DSUR", "DSUR")
        $modeClean = $modeClean.Replace("DOLBY AUDIO - DD + NEURAL:X", "NEURAL:X")
        $modeClean = $modeClean.Replace("DOLBY AUDIO - DD+", "DD+")
        $modeClean = $modeClean.Replace("DOLBY AUDIO - DD", "DD")

        # Catch any remaining oddball Denon strings.
        if ($modeClean -match "DSUR") { $modeClean = "DSUR" }
        if ($modeClean -match "NEURAL:X") { $modeClean = "NEURAL:X" }

        $detectedVisualMode = "STEREO"
        $detectedVisualModeCode = "0"

        # Combine raw and shortened signal strings for detection.
        $signalForVisual = "$inputSignal $displaySignal"

        # Dolby logo for true Atmos, or Dolby Digital/DD+ content using DSUR.
        # PCM + Dolby Surround remains VU meters.
        if (
            $modeClean -match "ATMOS" -or
            $signalForVisual -match "ATMOS" -or
            ($modeClean -eq "DSUR" -and $signalForVisual -match "DOLBY|DD")
        ) {
            $detectedVisualMode = "ATMOS"
            $detectedVisualModeCode = "1"
        }

        # If this poll returned blank data, keep the last known mode.
        if ([string]::IsNullOrWhiteSpace($mode) -and
            [string]::IsNullOrWhiteSpace($inputSignal) -and
            -not [string]::IsNullOrWhiteSpace($lastVisualMode)) {

            $visualMode = $lastVisualMode
            $visualModeCode = if ($lastVisualMode -eq "ATMOS") { "1" } else { "0" }
        }
        else {
            $visualMode = $detectedVisualMode
            $visualModeCode = $detectedVisualModeCode
        }

@"
Volume=$volume dB
Source=$source
Mode=$modeClean
VisualMode=$visualMode
VisualModeCode=$visualModeCode
InputSignal=$displaySignal
SampleRate=$sampleRate
SpeakerPreset=$speakerPreset
MultEQ=$multiEQ
DynamicEQ=$dynamicEQ
ReferenceLevelOffset=$rlo
DynamicVolume=$dynamicVolume
"@ | Set-Content $outFile

        if ($visualMode -ne $lastVisualMode) {
            & "C:\Program Files\Rainmeter\Rainmeter.exe" !RefreshApp
            $lastVisualMode = $visualMode
        }
    }
    catch {}

    Start-Sleep -Seconds 1
}
