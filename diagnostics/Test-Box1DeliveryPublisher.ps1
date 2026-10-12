$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\src\Box1Collector.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$assignment=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$PublisherScript'},$true)
$block=[scriptblock]::Create($assignment.Right.Extent.Text)
$publisher=$block.ToString().Trim().TrimStart('{').TrimEnd('}')
# Run the actual publisher in a unique HKCU fixture, never the production HKLM key.
$publisher=$publisher.Replace('[Box1Collector.NativeMethods]::HKEY_LOCAL_MACHINE','[IntPtr]::new(-2147483647)')
$id=[guid]::NewGuid().ToString('N')
$directory=Join-Path $PSScriptRoot "captures\PublisherTest-$id"
[void][IO.Directory]::CreateDirectory($directory)
$subkey="Software\OLED-Telemetry-Project\PublisherTest-$id"
$shared=[hashtable]::Synchronized(@{Stop=$false;LatestSample=$null})
$signal=[Threading.AutoResetEvent]::new($false)
$runspace=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace();$runspace.Open()
$worker=[PowerShell]::Create();$worker.Runspace=$runspace
[void]$worker.AddScript($publisher)
foreach($argument in @($shared,$signal,(Join-Path $directory 'status.txt'),(Join-Path $directory 'status.tmp'),(Join-Path $directory 'heartbeat.txt'),(Join-Path $directory 'heartbeat.tmp'),(Join-Path $directory 'error.txt'),(Join-Path $directory 'error.tmp'),2,$subkey)){[void]$worker.AddArgument($argument)}
$pending=$worker.BeginInvoke()
$registry=$null;$lock=$null;$fileTransitions=0;$lastWrite=[datetime]::MinValue
try {
    $deadline=[datetime]::UtcNow.AddSeconds(8)
    do {Start-Sleep -Milliseconds 50;$registry=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subkey)} while(-not $registry -and [datetime]::UtcNow -lt $deadline)
    if(-not $registry){throw ($worker.Streams.Error|Out-String)}
    for($sequence=1;$sequence -le 400;$sequence++) {
        $shared.LatestSample=[pscustomobject]@{Sequence=$sequence;Firmware='fixture';Port='fixture';LeftRmsDb=-20.0;RightRmsDb=-26.0;LeftPeakDb=-15.0;RightPeakDb=-21.0;LeftVuDb=-20.0;RightVuDb=-26.0;LeftLevel=.1;RightLevel=.05;LeftRmsEnvelope=.1;RightRmsEnvelope=.05;ReceiptTimestamp=[datetime]::Now}
        [void]$signal.Set();Start-Sleep -Milliseconds 10
        $path=Join-Path $directory 'status.txt'
        if(Test-Path $path){$stamp=[IO.File]::GetLastWriteTimeUtc($path);if($stamp -ne $lastWrite){$fileTransitions++;$lastWrite=$stamp}}
        if($sequence -eq 100){$lock=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}
        if($sequence -eq 250){
            $observed=[long]$registry.GetValue('Sequence')
            if($observed -lt 245){throw "Locked diagnostic file delayed live registry: $observed"}
            'PASS: diagnostic file replacement failure cannot stop live registry publication'
            $lock.Dispose();$lock=$null
        }
    }
    Start-Sleep -Milliseconds 250
    if([long]$registry.GetValue('Sequence') -ne 400){throw 'Latest synthetic sequence was not published'}
    if($fileTransitions -gt 50){throw "Diagnostic file is still written at acquisition rate: $fileTransitions"}
    if(((Get-Date)-(Get-Item (Join-Path $directory 'heartbeat.txt')).LastWriteTime).TotalSeconds -gt 3){throw 'Heartbeat stalled'}
    "PASS: full-rate registry; bounded 5 Hz diagnostic snapshots ($fileTransitions observed); heartbeat advances; final sequence commits"
    if([double]::Parse([string]$registry.GetValue('LeftRmsEnvelope'),[Globalization.CultureInfo]::InvariantCulture) -ne .1){throw 'Envelope changed during publication'}
    'PASS: publication preserves envelope values and stereo relationship'
} finally {
    if($lock){$lock.Dispose()};$shared.Stop=$true;[void]$signal.Set()
    if($pending.AsyncWaitHandle.WaitOne(5000)){[void]$worker.EndInvoke($pending)}else{$worker.Stop();throw 'Fixture publisher shutdown timed out'}
    if($registry){$registry.Dispose()}
    $worker.Dispose();$runspace.Dispose();$signal.Dispose()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subkey,$false)
}
