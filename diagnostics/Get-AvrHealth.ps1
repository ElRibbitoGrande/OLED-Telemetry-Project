param([string]$Root = 'C:\RainmeterDenon')
$ErrorActionPreference='Stop'
$path=Join-Path $Root 'avr_health.json'
if (-not (Test-Path -LiteralPath $path)) { throw 'Watchdog report absent; inspect TelemetryManager supervision.' }
$health=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[double]$health.Epoch
[pscustomobject]@{ReportAgeSeconds=$age;ReportCurrent=($age -ge -2 -and $age -lt 10);Health=$health} | ConvertTo-Json -Depth 12
