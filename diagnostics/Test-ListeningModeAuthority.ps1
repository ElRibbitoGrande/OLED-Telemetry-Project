$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Utilities\AvrHealth.ps1')
$observed=@{}
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\src\denon_status.ps1'),[ref]$tokens,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
foreach ($name in @('Format-ListeningMode','Apply-DecoderStatusFile','Process-DenonLine')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function Update-VisualMode {}
$state=@{Mode='';InputSignal='';SampleRate=''}
$collectingActiveChannels=$false
$decoderFile=Join-Path $PSScriptRoot 'captures\authority-test.txt'
[void][IO.Directory]::CreateDirectory((Split-Path $decoderFile))
try {
    [IO.File]::WriteAllText($decoderFile,"Mode=DOLBY SURROUND`nInputSignal=Stereo PCM`nSampleRate=48 kHz`nUpdated=$(Get-Date -Format o)")
    foreach ($source in @('HTPC','LYR+')) {
        $state.Source=$source
        foreach ($case in @(@('STEREO','STEREO'),@('DOLBY SURROUND','DOLBY SURROUND'),@('MCH STEREO','MULTICHANNEL STEREO'),@('STEREO','STEREO'))) {
            Process-DenonLine ('MS'+$case[0])
            1..5 | ForEach-Object {Apply-DecoderStatusFile}
            if ($state.Mode -cne $case[1]) {throw "Stale decoder overwrote mode for $source"}
            Process-DenonLine 'MSQUICK0'
            if ($state.Mode -cne $case[1]) {throw 'Quick Select corrupted mode'}
            if ($state.InputSignal -ne 'Stereo PCM') {throw 'Separate decoder signal import failed'}
        }
    }
    [IO.File]::WriteAllText($decoderFile,"Mode=DOLBY ATMOS`nInputSignal=Dolby Atmos`nUpdated=2000-01-01")
    Apply-DecoderStatusFile
    if ($state.Mode -ne 'STEREO' -or $state.InputSignal -ne '') {throw 'Expired decoder state was trusted'}
    $decoderFile += '.missing'
    Apply-DecoderStatusFile
    if ($state.Mode -ne 'STEREO') {throw 'Missing decoder changed mode'}
    $activeChannelStateKeys=[ordered]@{FL='ActiveFL';FR='ActiveFR';C='ActiveC';SW='ActiveSUB1';SW2='ActiveSUB2'}
    $pendingActiveChannels=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Reconnect tails and individual channel events must not create partial maps.
    Process-DenonLine 'CVSW2 50'; Process-DenonLine 'CVEND'
    if ($state.ContainsKey('ActiveSUB2')) {throw 'Orphan response tail published'}
    foreach($line in @('CVFL 50','CVFR 50','CVC 50','CVSW 50','CVSW2 50','CVEND')) {Process-DenonLine $line}
    if ($state.ActiveFL -ne 1 -or $state.ActiveC -ne 1 -or $state.ActiveSUB2 -ne 1) {throw 'Full topology failed'}
    foreach($line in @('CVFL 50','CVFR 50')) {Process-DenonLine $line}
    if ($state.ActiveC -ne 1) {throw 'Incomplete transaction published'}
    foreach($line in @('CVFL 50','CVFR 50','CVSW 50','CVSW2 50','CVEND')) {Process-DenonLine $line}
    if ($state.ActiveC -ne 0 -or $state.ActiveFL -ne 1 -or $state.ActiveSUB2 -ne 1) {throw 'Stereo replacement topology failed'}
    'PASS: orphan tails ignored; complete topology committed; partial topology retained; restarted response replaces partial frame.'
    'PASS: parser; stale/missing decoder; same-source mode sequence; HTPC and LYR+ semantics; Quick Select exclusion; separate PCM signal.'
} finally {
    $testFile=Join-Path $PSScriptRoot 'captures\authority-test.txt'
    if (Test-Path -LiteralPath $testFile) {Remove-Item -LiteralPath $testFile}
}
