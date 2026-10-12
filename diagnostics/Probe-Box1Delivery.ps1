[CmdletBinding()]
param([Parameter(Mandatory)][string]$CaptureDirectory,[ValidateRange(5,330)][int]$MaximumSeconds=120)
$ErrorActionPreference='Stop'
$captureRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'captures')).TrimEnd('\')+'\'
$CaptureDirectory=[IO.Path]::GetFullPath($CaptureDirectory)
if(-not $CaptureDirectory.StartsWith($captureRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Probe output must stay in ignored capture directory'}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Globalization;
using Microsoft.Win32;
public static class Box1DeliveryProbe {
 public static void Run(string directory,string control,int seconds) {
  using(var key=RegistryKey.OpenBaseKey(RegistryHive.LocalMachine,RegistryView.Registry64).OpenSubKey("Software\\OLED-Telemetry-Project\\Box1Runtime",RegistryKeyPermissionCheck.ReadWriteSubTree,System.Security.AccessControl.RegistryRights.ReadKey|System.Security.AccessControl.RegistryRights.SetValue)) {
   if(key==null)throw new Exception("Box1 runtime key unavailable");
   using(var writer=new StreamWriter(Path.Combine(directory,"box1_delivery.csv"))) {
    writer.WriteLine("ObservedUtcMs,ReceiptUtcMs,Sequence,LeftRmsDb,RightRmsDb,LeftEnvelope,RightEnvelope");
    var clock=Stopwatch.StartNew();string previous="";
    File.WriteAllText(Path.Combine(directory,"delivery_probe.started"),"Bounded read-only observation plus diagnostic clock value");
    while(clock.Elapsed.TotalSeconds<seconds && File.Exists(control)) {
     double now=(DateTime.UtcNow.Ticks-621355968000000000L)/10000.0;
     key.SetValue("DiagnosticClockUtcMs",now.ToString("R",CultureInfo.InvariantCulture),RegistryValueKind.String);
     string first=Convert.ToString(key.GetValue("Sequence"));
     string stamp=Convert.ToString(key.GetValue("Updated"));
     string left=Convert.ToString(key.GetValue("LeftRmsDb"));string right=Convert.ToString(key.GetValue("RightRmsDb"));
     string el=Convert.ToString(key.GetValue("LeftRmsEnvelope"));string er=Convert.ToString(key.GetValue("RightRmsEnvelope"));
     string last=Convert.ToString(key.GetValue("Sequence"));DateTime receipt;
     if(first==last && last!=previous && DateTime.TryParseExact(stamp,"yyyy-MM-dd HH:mm:ss.fff",CultureInfo.InvariantCulture,DateTimeStyles.AssumeLocal,out receipt)) {
      double rm=(receipt.ToUniversalTime().Ticks-621355968000000000L)/10000.0;
      writer.WriteLine(string.Join(",",new[]{now.ToString("R",CultureInfo.InvariantCulture),rm.ToString("R",CultureInfo.InvariantCulture),last,left,right,el,er}));previous=last;
     }
     Thread.Sleep(5);
    }
   }
  }
  File.WriteAllText(Path.Combine(directory,"delivery_probe.complete"),"Completed bounded capture; clock is no longer advancing");
 }
}
'@
try {[Box1DeliveryProbe]::Run($CaptureDirectory,(Join-Path $PSScriptRoot 'Box1VUComparison.capture'),$MaximumSeconds)}
catch {[IO.File]::WriteAllText((Join-Path $CaptureDirectory 'delivery_probe.error.txt'),($_|Out-String));throw}
