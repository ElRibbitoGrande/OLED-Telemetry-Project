$ErrorActionPreference = "Stop"

$developmentFolder = "C:\RainmeterDenon\Development"
$resultFile = Join-Path $developmentFolder "decoder_test_result.txt"
$errorFile = Join-Path $developmentFolder "decoder_test_error.txt"

New-Item -ItemType Directory -Path $developmentFolder -Force | Out-Null
Remove-Item $resultFile, $errorFile -Force -ErrorAction SilentlyContinue

$cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$url = "https://192.168.0.128:10443/ajax/general/get_config?type=12&_=$cacheBust"

try {
    $raw = (& "$env:SystemRoot\System32\curl.exe" -k -s --max-time 5 $url) -join "`n"

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "curl.exe returned an empty response."
    }

    [xml]$xml = $raw

    $soundMode = [string]$xml.Information.Audio.SoundMode
    $inputSignal = [string]$xml.Information.Audio.InputSignal
    $sampleRate = [string]$xml.Information.Audio.SampleRate

    @"
Status=Success
SoundMode=$soundMode
InputSignal=$inputSignal
SampleRate=$sampleRate
Updated=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff")
"@ | Set-Content -LiteralPath $resultFile -Encoding UTF8

    Write-Host "Decoder test succeeded."
    Write-Host "Result written to: $resultFile"
}
catch {
    @"
Status=Failure
Error=$($_.Exception.Message)
Updated=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff")
"@ | Set-Content -LiteralPath $errorFile -Encoding UTF8

    Write-Host "Decoder test failed."
    Write-Host "Error written to: $errorFile"
    exit 1
}
