[CmdletBinding()]
param(
    [ValidateRange(5,180)][int]$Seconds = 60,
    [string]$RuntimeRoot = 'C:\RainmeterDenon',
    [switch]$Passive
)

# Observation only: queries AVR state; never sends mode/source/volume controls.
# Uses a separate bounded socket and never restarts a production collector.
$ErrorActionPreference = 'Stop'
$capture = Join-Path $PSScriptRoot ('captures\ListeningMode_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
[void][IO.Directory]::CreateDirectory($capture)
$collector = [IO.File]::ReadAllText((Join-Path $RuntimeRoot 'denon_status.ps1'))
if ($collector -notmatch '(?m)^\$ip\s*=\s*"([^"]+)"') { throw 'Cannot find configured AVR address.' }
$avrAddress = $Matches[1]
$log = [IO.StreamWriter]::new((Join-Path $capture 'capture.jsonl'), $false, [Text.UTF8Encoding]::new($false))
$log.AutoFlush = $true
$client = [Net.Sockets.TcpClient]::new()
$stream = $null
function Record([string]$Kind, $Value) {
    $log.WriteLine((@{ utc=[DateTime]::UtcNow.ToString('o'); kind=$Kind; value=$Value } | ConvertTo-Json -Compress -Depth 5))
}
try {
    $connect = $client.ConnectAsync($avrAddress, 23)
    if (-not $connect.Wait(2000)) { throw 'Diagnostic TCP connection timed out.' }
    $stream = $client.GetStream()
    $stream.WriteTimeout = 500
    Record 'capture' "Independent TCP observer; Passive=$Passive; otherwise queries MS? once per second. File samples every 25ms. Rainmeter internal values are not directly observed."
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $nextQuery = [DateTime]::MinValue
    $buffer = New-Object byte[] 8192
    $pending = ''
    $last = @{}
    Write-Output "CAPTURE_READY $capture"
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not $Passive -and [DateTime]::UtcNow -ge $nextQuery) {
            $query = [Text.Encoding]::ASCII.GetBytes("MS?`r")
            $stream.Write($query, 0, $query.Length)
            Record 'query' 'MS?'
            $nextQuery = [DateTime]::UtcNow.AddSeconds(1)
        }
        if ($stream.DataAvailable) {
            $count = $stream.Read($buffer, 0, $buffer.Length)
            $pending += [Text.Encoding]::ASCII.GetString($buffer, 0, $count)
            $lines = $pending -split "`r"
            $pending = $lines[-1]
            for ($i=0; $i -lt $lines.Length-1; $i++) { Record 'tcp' $lines[$i].Trim() }
        }
        foreach ($name in @('denon_status.txt','decoder_status.txt','decoder_status_error.txt','telemetry_manager_status.txt')) {
            try {
                $value = [IO.File]::ReadAllText((Join-Path $RuntimeRoot $name))
                if ($last[$name] -cne $value) { Record $name $value; $last[$name] = $value }
            } catch { Record 'read_error' ($name + ': ' + $_.Exception.Message) }
        }
        Start-Sleep -Milliseconds 25
    }
    Record 'complete' $Seconds
} catch {
    Record 'error' $_.Exception.Message
    throw
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
    $client.Dispose()
    $log.Dispose()
}
Write-Output "CAPTURE_COMPLETE $capture"
