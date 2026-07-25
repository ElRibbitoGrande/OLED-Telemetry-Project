$ErrorActionPreference = "Continue"

$dev = "C:\RainmeterDenon\Development"
New-Item -ItemType Directory -Path $dev -Force | Out-Null

$report = Join-Path $dev "decoder_transport_report.txt"
$curlOut = Join-Path $dev "decoder_curl_output.xml"
$curlErr = Join-Path $dev "decoder_curl_stderr.txt"
$cmdOut = Join-Path $dev "decoder_cmd_output.xml"
$cmdErr = Join-Path $dev "decoder_cmd_stderr.txt"
$iwrOut = Join-Path $dev "decoder_iwr_output.xml"

Remove-Item $report,$curlOut,$curlErr,$cmdOut,$cmdErr,$iwrOut -Force -ErrorAction SilentlyContinue

$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$url = "https://192.168.0.128:10443/ajax/general/get_config?type=12&_=$stamp"
$curl = "$env:SystemRoot\System32\curl.exe"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("URL=$url")
$lines.Add("PowerShellVersion=$($PSVersionTable.PSVersion)")
$lines.Add("User=$env:USERNAME")
$lines.Add("")

# Test 1: native curl.exe invoked directly by PowerShell.
try {
    & $curl -k -v --connect-timeout 5 --max-time 10 -o $curlOut $url 2> $curlErr
    $exit = $LASTEXITCODE
    $size = if (Test-Path $curlOut) { (Get-Item $curlOut).Length } else { 0 }
    $lines.Add("[Direct curl]")
    $lines.Add("ExitCode=$exit")
    $lines.Add("OutputBytes=$size")
    if (Test-Path $curlErr) {
        $lines.Add("Stderr:")
        $lines.AddRange([string[]](Get-Content $curlErr))
    }
} catch {
    $lines.Add("[Direct curl]")
    $lines.Add("Exception=$($_.Exception.Message)")
}
$lines.Add("")

# Test 2: exact curl command through cmd.exe, removing PowerShell native-command binding.
try {
    $cmdLine = "`"$curl`" -k -v --connect-timeout 5 --max-time 10 -o `"$cmdOut`" `"$url`" 2>`"$cmdErr`""
    $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList "/d /c $cmdLine" -Wait -PassThru -WindowStyle Hidden
    $size = if (Test-Path $cmdOut) { (Get-Item $cmdOut).Length } else { 0 }
    $lines.Add("[cmd.exe curl]")
    $lines.Add("ExitCode=$($p.ExitCode)")
    $lines.Add("OutputBytes=$size")
    if (Test-Path $cmdErr) {
        $lines.Add("Stderr:")
        $lines.AddRange([string[]](Get-Content $cmdErr))
    }
} catch {
    $lines.Add("[cmd.exe curl]")
    $lines.Add("Exception=$($_.Exception.Message)")
}
$lines.Add("")

# Test 3: Invoke-WebRequest with certificate validation disabled for this process.
try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 `
        -Headers @{ "Cache-Control"="no-cache"; "Pragma"="no-cache"; "User-Agent"="Mozilla/5.0" }
    $content = [string]$response.Content
    Set-Content -LiteralPath $iwrOut -Value $content -Encoding UTF8
    $lines.Add("[Invoke-WebRequest]")
    $lines.Add("StatusCode=$($response.StatusCode)")
    $lines.Add("OutputBytes=$([Text.Encoding]::UTF8.GetByteCount($content))")
} catch {
    $lines.Add("[Invoke-WebRequest]")
    $lines.Add("Exception=$($_.Exception.Message)")
}
$lines.Add("")

foreach ($candidate in @($curlOut,$cmdOut,$iwrOut)) {
    if (Test-Path $candidate) {
        try {
            [xml]$x = Get-Content $candidate -Raw
            $lines.Add("[Parsed $([IO.Path]::GetFileName($candidate))]")
            $lines.Add("SoundMode=$([string]$x.Information.Audio.SoundMode)")
            $lines.Add("InputSignal=$([string]$x.Information.Audio.InputSignal)")
            $lines.Add("SampleRate=$([string]$x.Information.Audio.SampleRate)")
        } catch {
            $lines.Add("[Parsed $([IO.Path]::GetFileName($candidate))]")
            $lines.Add("XMLException=$($_.Exception.Message)")
        }
        $lines.Add("")
    }
}

$lines | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host "Diagnostic complete: $report"
