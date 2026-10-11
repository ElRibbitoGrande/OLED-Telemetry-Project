$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\src'
. (Join-Path $source 'Utilities\AvrHealth.ps1')
Import-AvrValueParsers (Join-Path $source 'denon_status.ps1')
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }; "PASS: $Message"
}
foreach ($file in @('denon_status.ps1','AvrWatchdog.ps1','TelemetryManager.ps1','TelemetryProcessControl.ps1','Utilities\AvrHealth.ps1')) {
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $source $file),[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) "PowerShell parser $file"
}
$now = Get-AvrEpoch
$observation = [pscustomobject]@{Epoch=$now;Observed=[pscustomobject]@{Power=$now;Source=$now;Mode=$now;Volume=$now};Values=[pscustomobject]@{Power='ON';Source='HTPC';Mode='DOLBY SURROUND';Volume='-19.5'}}
Assert (Get-AvrCollectorFresh $observation $now) 'Unchanged values with fresh observations are healthy'
$observation.Observed.Source = $now-16
Assert (-not (Get-AvrCollectorFresh $observation $now)) 'Alive collector with fresh heartbeat but stale source is unhealthy'
$observation.Observed.Source=$now; $observation.Epoch=$now-9
Assert (-not (Get-AvrCollectorFresh $observation $now)) 'Terminated or frozen collector publication expires'
Assert (-not (Get-AvrCollectorFresh $null $now)) 'Missing startup observation cannot validate persisted state'
$observation.Epoch=$now+60
Assert (-not (Get-AvrCollectorFresh $observation $now)) 'Future timestamps cannot validate state'
$argsPolicy=@{Failures=6;FailureSeconds=181;IdentityVerified=$true;CollectorFresh=$false;ReconnectAttempted=$true;RestartAttempted=$true;BaselineVerified=$true}
Assert (Get-AvrResetEligible @argsPolicy) 'Persistent independent control failures with identified AVR and failed recovery permit warning'
foreach ($key in @('IdentityVerified','ReconnectAttempted','RestartAttempted','BaselineVerified')) {
    $copy=$argsPolicy.Clone();$copy[$key]=$false
    Assert (-not (Get-AvrResetEligible @copy)) "No RESET AVR without $key"
}
$copy=$argsPolicy.Clone();$copy.CollectorFresh=$true
Assert (-not (Get-AvrResetEligible @copy)) 'Healthy collector rules out warning from competing probe failure'
$copy=$argsPolicy.Clone();$copy.Failures=1
Assert (-not (Get-AvrResetEligible @copy)) 'Single timeout cannot trigger warning'
$copy=$argsPolicy.Clone();$copy.FailureSeconds=90
Assert (-not (Get-AvrResetEligible @copy)) 'Temporary failure remains silent'
$copy=$argsPolicy.Clone();$copy.PowerBeforeFailure='STANDBY'
Assert (-not (Get-AvrResetEligible @copy)) 'Previous verified standby prevents ambiguous power-save control outages from recommending reset'

# Local CR-fragmenting fake AVR; background .NET threads never touch physical AVR.
if (-not ('AvrFixture' -as [type])) {
Add-Type @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public class AvrFixture : IDisposable {
    TcpListener listener; Thread thread; volatile bool running=true;
    public volatile bool Silent=false; public volatile bool Drop=false;
    public int Port; public int Mutations=0;
    public AvrFixture() {
        listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
        Port=((IPEndPoint)listener.LocalEndpoint).Port;
        thread=new Thread(Run);thread.IsBackground=true;thread.Start();
    }
    void Run() {
        while(running) {
            try { var c=listener.AcceptTcpClient(); var t=new Thread(()=>Handle(c));t.IsBackground=true;t.Start(); }
            catch { }
        }
    }
    void Handle(TcpClient c) {
        using(c) { try {
            var s=c.GetStream();s.ReadTimeout=5000;var b=new byte[1024];string pending="";
            while(running) {
                int n=s.Read(b,0,b.Length);if(n==0)return;
                pending+=Encoding.ASCII.GetString(b,0,n);
                int end;
                while((end=pending.IndexOf('\r'))>=0) {
                    string q=pending.Substring(0,end);pending=pending.Substring(end+1);
                    string reply="";
                    switch(q) {
                        case "PW?":reply="PWON\r";break;
                        case "SI?":reply="SISAT/CBL\r";break;
                        case "MV?":reply="MVMAX 81\rMV605\r";break;
                        case "MS?":reply="MSDOLBY AUDIO-DSUR\r";break;
                        case "CV?":reply="CVFL 50\rCVFR 50\rCVSW 50\rCVSW2 50\rCVEND\r";break;
                        case "MSQUICK ?":reply="MSQUICK0\rMSQUICK1\r";break;
                        default:Interlocked.Increment(ref Mutations);break;
                    }
                    if(Drop)return;
                    if(Silent)continue;
                    byte[] r=Encoding.ASCII.GetBytes(reply);
                    if(r.Length>1){s.Write(r,0,r.Length-1);Thread.Sleep(4);s.Write(r,r.Length-1,1);}
                }
            }
        } catch {} }
    }
    public void Dispose(){running=false;listener.Stop();thread.Join(1000);}
}
'@
}
$server=[AvrFixture]::new()
$testRoot=Join-Path $PSScriptRoot ('captures\WatchdogTest-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($testRoot)
try {
    $result=Get-AvrVerification -AvrHost '127.0.0.1' -Port $server.Port -Comprehensive
    if (-not $result.Valid) { throw ($result | ConvertTo-Json -Depth 5) }
    Assert ($result.Valid -and $result.ChannelsComplete) 'Fresh comprehensive query parses fragmented CR-only protocol'
    Assert ($result.Values.Mode -eq 'DOLBY SURROUND' -and $result.Values.Source -eq 'HTPC' -and $result.Values.Volume -eq '-19.5') 'Independent query normalizes mode/source/half-step volume and excludes MAX/QUICK'
    $server.Silent=$true
    $result=Get-AvrVerification -AvrHost '127.0.0.1' -Port $server.Port -TimeoutMilliseconds 600
    Assert ($result.TcpConnected -and -not $result.Valid -and $result.ElapsedMilliseconds -lt 1500) 'Responsive TCP with silent control is bounded and invalid'
    $server.Silent=$false;$server.Drop=$true
    $result=Get-AvrVerification -AvrHost '127.0.0.1' -Port $server.Port -TimeoutMilliseconds 600
    Assert (-not $result.Valid) 'Dropped fresh connection cannot verify state'
    $server.Drop=$false
    $result=Get-AvrVerification -AvrHost '127.0.0.1' -Port $server.Port
    Assert $result.Valid 'Authoritative communication recovers after interruption'
    Copy-Item (Join-Path $source 'denon_status.ps1') $testRoot
    $now=Get-AvrEpoch;$observation.Epoch=$now
    foreach($key in @('Power','Source','Mode','Volume')) {$observation.Observed.$key=$now}
    Write-AvrJson (Join-Path $testRoot 'avr_collector_observation.json') $observation
    [IO.File]::WriteAllText((Join-Path $testRoot 'denon_status.txt'),"Source=HTPC`nMode=DOLBY SURROUND`nVolume=-19.5 dB`n")
    & (Join-Path $source 'AvrWatchdog.ps1') -Root $testRoot -AvrHost '127.0.0.1' -Port $server.Port -MaximumCycles 1 -DisableRecovery -WatchdogMutexName ('Local\AvrWatchdogTest'+[guid]::NewGuid())
    $health=Read-AvrJson (Join-Path $testRoot 'avr_health.json')
    Assert ($health.Overall -eq 'Healthy' -and $health.Trusted -and -not $health.ResetAvr) 'Isolated watchdog integration verifies healthy canonical state silently'
    [IO.File]::WriteAllText((Join-Path $testRoot 'denon_status.txt'),"Source=LYR+`nMode=STEREO`nVolume=-28.5 dB`n")
    & (Join-Path $source 'AvrWatchdog.ps1') -Root $testRoot -AvrHost '127.0.0.1' -Port $server.Port -MaximumCycles 1 -DisableRecovery -WatchdogMutexName ('Local\AvrWatchdogTest'+[guid]::NewGuid())
    $health=Read-AvrJson (Join-Path $testRoot 'avr_health.json')
    Assert ($health.Overall -eq 'StateMismatch' -and -not $health.Trusted -and -not $health.ResetAvr) 'Stale canonical/source/logo input is detected without blaming AVR'
    [void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'Utilities'))
    [void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'Development'))
    Copy-Item (Join-Path $source 'Utilities\AvrHealth.ps1') (Join-Path $testRoot 'Utilities')
    $fixtureProcess=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f (Join-Path $testRoot 'denon_status.ps1')),
        '-Root',('"{0}"' -f $testRoot),'-AvrHost','127.0.0.1','-AvrPort',$server.Port,
        '-DisableOptionalPolling','-CollectorMutexName',('Local\AvrCollectorTest'+[guid]::NewGuid()))
    $deadline=[datetime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $live=Read-AvrJson (Join-Path $testRoot 'avr_collector_observation.json')
    } while(($live.PID -ne $fixtureProcess.Id -or -not (Get-AvrCollectorFresh $live (Get-AvrEpoch))) -and [datetime]::UtcNow -lt $deadline)
    Assert ($live.PID -eq $fixtureProcess.Id -and (Get-AvrCollectorFresh $live (Get-AvrEpoch))) 'Actual collector reconciles persisted obsolete state against localhost AVR at startup'
    Assert ($live.Values.Source -eq 'HTPC' -and $live.Values.Mode -eq 'DOLBY SURROUND') 'Actual collector consumes CR-fragmented authoritative mode and source'
    $server.Silent=$true
    Start-Sleep -Seconds 17
    $live=Read-AvrJson (Join-Path $testRoot 'avr_collector_observation.json')
    $fixtureProcess.Refresh()
    Assert (-not $fixtureProcess.HasExited -and -not (Get-AvrCollectorFresh $live (Get-AvrEpoch))) 'Actual collector remains alive while silent-control observations expire independently'
    $server.Silent=$false
    $deadline=[datetime]::UtcNow.AddSeconds(12)
    do {Start-Sleep -Milliseconds 200;$live=Read-AvrJson (Join-Path $testRoot 'avr_collector_observation.json')} while(-not (Get-AvrCollectorFresh $live (Get-AvrEpoch)) -and [datetime]::UtcNow -lt $deadline)
    Assert (Get-AvrCollectorFresh $live (Get-AvrEpoch)) 'Actual collector automatically reconnects and resumes after silent control returns'
    Assert ($server.Mutations -eq 0) 'All fixture traffic consists solely of allowlisted read-only queries'
} finally {
    if($fixtureProcess -and -not $fixtureProcess.HasExited){$fixtureProcess.Kill();[void]$fixtureProcess.WaitForExit(3000);$fixtureProcess.Dispose()}
    $server.Dispose()
}
"Evidence preserved at $testRoot"
