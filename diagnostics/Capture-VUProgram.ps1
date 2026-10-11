[CmdletBinding()]
param(
    [ValidateRange(10,300)][int]$Seconds=90,
    [ValidateSet('','HTPC','LYR+')][string]$ExpectedSource='',
    [string]$ExpectedTitle='',
    [ValidateRange(0,180)][int]$WaitForMatchSeconds=0
)
$ErrorActionPreference='Stop'
$started=$false
if($ExpectedSource -or $ExpectedTitle) {
    $matchDeadline=[DateTime]::UtcNow.AddSeconds($WaitForMatchSeconds)
    Write-Output "ARMED: waiting for source '$ExpectedSource', title '$ExpectedTitle'"
    do {
        $matched=$false
        try {
            $denon=[IO.File]::ReadAllText('C:\RainmeterDenon\denon_status.txt')
            $metadata=[IO.File]::ReadAllText('C:\RainmeterDenon\NowPlaying\now_playing.txt')
            $actual=[regex]::Match($denon,'(?m)^Source=([^\r\n]*)').Groups[1].Value
            $title=[regex]::Match($metadata,'(?m)^Title=([^\r\n]*)').Groups[1].Value
            $matched=(-not $ExpectedSource -or $actual -eq $ExpectedSource) -and (-not $ExpectedTitle -or $title -eq $ExpectedTitle)
        } catch {}
        if($matched) {break}
        if([DateTime]::UtcNow -ge $matchDeadline) {throw 'Expected source/title not observed; capture was not started.'}
        Start-Sleep -Milliseconds 500
    } while($true)
}
try {
    & (Join-Path $PSScriptRoot 'Start-Box1VUComparisonCapture.ps1')
    $started=$true
    $control=@{}
    foreach($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Box1VUComparison.capture')) {
        if($line -match '^([^=]+)=(.*)$') {$control[$Matches[1]]=$Matches[2]}
    }
    $capturePath=$control.CaptureDirectory
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    $contextPath=Join-Path $capturePath 'track-context.log'
    while([DateTime]::UtcNow -lt $deadline) {
        try {
            $state=[IO.File]::ReadAllText('C:\RainmeterDenon\NowPlaying\now_playing.txt')
            $fields=([regex]::Matches($state,'(?m)^(Source|Title|Artist|Album|PlaybackStatus|PositionSeconds|DurationSeconds)=.*') | ForEach-Object Value) -join "`n"
            Add-Content -LiteralPath $contextPath -Value ([DateTime]::UtcNow.ToString('o')+"`n"+$fields) -Encoding UTF8
        } catch {
            # Context is optional: a reader/antivirus file lock must not abort
            # the independent high-rate signal capture or its fixed duration.
            $contextError=$_.Exception.Message
            try {
                Add-Content -LiteralPath $contextPath -Value ([DateTime]::UtcNow.ToString('o')+' ContextReadError='+$contextError) -Encoding UTF8
            } catch {
                Write-Warning 'Skipped an unavailable track-context log sample; signal capture continues.'
            }
        }
        Start-Sleep -Milliseconds 1000
    }
} finally {
    if($started) {& (Join-Path $PSScriptRoot 'Stop-Box1VUComparisonCapture.ps1')}
}
