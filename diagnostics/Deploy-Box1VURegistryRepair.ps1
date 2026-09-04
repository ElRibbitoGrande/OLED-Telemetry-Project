[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This deployment must be run from an Administrator token.'
}

$repo = 'C:\OLED-Telemetry-Project'
$backupRoot = Join-Path 'C:\RainmeterDenon\Backups\Box1-VU-Lyr-Repair' (
    Get-Date -Format 'yyyyMMdd_HHmmss_fff'
)
$registryParentRelativePath = 'SOFTWARE\OLED-Telemetry-Project'
$registryRelativePath = 'SOFTWARE\OLED-Telemetry-Project\Box1Runtime'
$registryDisplayPath = 'HKLM\SOFTWARE\OLED-Telemetry-Project\Box1Runtime'
$items = @(
    [pscustomobject]@{
        Name = 'Box1Collector.ps1'
        Source = Join-Path $repo 'src\Box1Collector.ps1'
        Destination = 'C:\RainmeterDenon\Box1Collector.ps1'
    }
    [pscustomobject]@{
        Name = 'DashboardTelemetry.inc'
        Source = Join-Path $repo 'src\@Resources\Includes\DashboardTelemetry.inc'
        Destination = 'C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Analog_Floating2\@Resources\Includes\DashboardTelemetry.inc'
    }
)

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$registryView = [Microsoft.Win32.RegistryView]::Registry64
$localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    $registryView
)
try {
    $parentProbe = $localMachine.OpenSubKey($registryParentRelativePath)
    $registryParentExisted = $null -ne $parentProbe
    if ($null -ne $parentProbe) { $parentProbe.Dispose() }
    $keyProbe = $localMachine.OpenSubKey($registryRelativePath)
    $registryExisted = $null -ne $keyProbe
    $priorRegistrySddl = if ($registryExisted) {
        $keyProbe.GetAccessControl().GetSecurityDescriptorSddlForm(
            [Security.AccessControl.AccessControlSections]::All
        )
    } else { '' }
    if ($null -ne $keyProbe) { $keyProbe.Dispose() }
}
finally {
    $localMachine.Dispose()
}
$manifest = [System.Collections.Generic.List[object]]::new()

try {
    foreach ($item in $items) {
        $backup = Join-Path $backupRoot ($item.Name + '.pre')
        Copy-Item -LiteralPath $item.Destination -Destination $backup -Force
        $manifest.Add([pscustomobject]@{
            Name = $item.Name
            Source = $item.Source
            Destination = $item.Destination
            Backup = $backup
            PreSHA256 = (Get-FileHash -LiteralPath $item.Destination).Hash
            SourceSHA256 = (Get-FileHash -LiteralPath $item.Source).Hash
        })
    }
    $manifest | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $backupRoot 'manifest.csv')

    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $restrictedSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-12')
    $inheritance = [Security.AccessControl.InheritanceFlags]::None
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $publisherRights = [Security.AccessControl.RegistryRights]::ReadKey -bor
        [Security.AccessControl.RegistryRights]::SetValue
    $readerRights = [Security.AccessControl.RegistryRights]::ReadKey
    $localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        $registryView
    )
    try {
        $runtimeKey = $localMachine.CreateSubKey(
            $registryRelativePath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree
        )
        if ($null -eq $runtimeKey) { throw 'RegistryKey.CreateSubKey returned no key.' }
        $acl = $runtimeKey.GetAccessControl()
        $acl.SetAccessRule([Security.AccessControl.RegistryAccessRule]::new(
            $currentUserSid, $publisherRights, $inheritance, $propagation, $allow
        ))
        $acl.SetAccessRule([Security.AccessControl.RegistryAccessRule]::new(
            $restrictedSid, $readerRights, $inheritance, $propagation, $allow
        ))
        $runtimeKey.SetAccessControl($acl)
        $deployedSddl = $runtimeKey.GetAccessControl().GetSecurityDescriptorSddlForm(
            [Security.AccessControl.AccessControlSections]::All
        )
        $runtimeKey.Dispose()
    }
    finally {
        $localMachine.Dispose()
    }
    @(
        "RegistryPath=$registryDisplayPath"
        "RegistryParentExisted=$registryParentExisted"
        "RegistryExisted=$registryExisted"
        "PriorSddl=$priorRegistrySddl"
        "DeployedSddl=$deployedSddl"
    ) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $backupRoot 'registry-manifest.txt')

    foreach ($item in $items) {
        Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force
        $sourceHash = (Get-FileHash -LiteralPath $item.Source).Hash
        $deployedHash = (Get-FileHash -LiteralPath $item.Destination).Hash
        if ($sourceHash -ne $deployedHash) {
            throw "Deployed hash mismatch for $($item.Name)."
        }
    }

    $before = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'powershell.exe' -and $_.CommandLine -match '[\\]Box1Collector\.ps1'
    })
    if ($before.Count -ne 1) {
        throw "Expected one Box1 collector before restart; found $($before.Count)."
    }
    $oldPid = $before[0].ProcessId
    Stop-Process -Id $oldPid -Force

    $deadline = (Get-Date).AddSeconds(25)
    do {
        Start-Sleep -Milliseconds 500
        $after = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -eq 'powershell.exe' -and $_.CommandLine -match '[\\]Box1Collector\.ps1'
        })
    } while ((Get-Date) -lt $deadline -and
        ($after.Count -ne 1 -or $after[0].ProcessId -eq $oldPid))
    if ($after.Count -ne 1 -or $after[0].ProcessId -eq $oldPid) {
        throw 'TelemetryManager did not restore exactly one new Box1 collector.'
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 250
        $localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine, $registryView
        )
        try {
            $runtimeKey = $localMachine.OpenSubKey($registryRelativePath)
            $runtime = if ($null -ne $runtimeKey) {
                [pscustomobject]@{
                    Connected = $runtimeKey.GetValue('Connected', '')
                    Ready = $runtimeKey.GetValue('Ready', '')
                    Sequence = $runtimeKey.GetValue('Sequence', '')
                }
            } else { $null }
            if ($null -ne $runtimeKey) { $runtimeKey.Dispose() }
        }
        finally { $localMachine.Dispose() }
    } while ((Get-Date) -lt $deadline -and $null -eq $runtime)
    if ($null -eq $runtime) {
        throw 'The HKLM Box1 runtime key was not published.'
    }
    $sequence1 = [long]$runtime.Sequence
    Start-Sleep -Milliseconds 600
    $localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $registryView
    )
    try {
        $runtimeKey = $localMachine.OpenSubKey($registryRelativePath)
        $runtime2 = [pscustomobject]@{
            Connected = $runtimeKey.GetValue('Connected', '')
            Ready = $runtimeKey.GetValue('Ready', '')
            Sequence = $runtimeKey.GetValue('Sequence', '')
        }
        $runtimeKey.Dispose()
    }
    finally { $localMachine.Dispose() }
    $sequence2 = [long]$runtime2.Sequence
    if ($runtime2.Connected -ne '1' -or $runtime2.Ready -ne '1' -or $sequence2 -le $sequence1) {
        throw 'The HKLM Box1 runtime stream is not healthy and advancing.'
    }

    @(
        'Result=PASS'
        "BackupRoot=$backupRoot"
        "OldPID=$oldPid"
        "NewPID=$($after[0].ProcessId)"
        "Sequence1=$sequence1"
        "Sequence2=$sequence2"
        "SequenceDelta=$($sequence2 - $sequence1)"
        "Completed=$(Get-Date -Format o)"
    ) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $backupRoot 'deployment-result.txt')
}
catch {
    foreach ($entry in $manifest) {
        Copy-Item -LiteralPath $entry.Backup -Destination $entry.Destination -Force -ErrorAction SilentlyContinue
    }
    $rollbackCollectors = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'powershell.exe' -and $_.CommandLine -match '[\\]Box1Collector\.ps1'
    })
    foreach ($collector in $rollbackCollectors) {
        Stop-Process -Id $collector.ProcessId -Force -ErrorAction SilentlyContinue
    }
    $localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $registryView
    )
    try {
        if ($registryExisted -and -not [string]::IsNullOrWhiteSpace($priorRegistrySddl)) {
            $runtimeKey = $localMachine.OpenSubKey(
                $registryRelativePath,
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                [Security.AccessControl.RegistryRights]::ChangePermissions
            )
            $rollbackAcl = $runtimeKey.GetAccessControl()
            $rollbackAcl.SetSecurityDescriptorSddlForm($priorRegistrySddl)
            $runtimeKey.SetAccessControl($rollbackAcl)
            $runtimeKey.Dispose()
        }
        else {
            $localMachine.DeleteSubKeyTree($registryRelativePath, $false)
        }
        if (-not $registryParentExisted) {
            $localMachine.DeleteSubKeyTree($registryParentRelativePath, $false)
        }
    }
    catch {}
    finally { $localMachine.Dispose() }
    @(
        'Result=FAIL'
        "BackupRoot=$backupRoot"
        "Error=$($_.Exception.Message)"
        "Position=$($_.InvocationInfo.PositionMessage -replace "`r?`n", ' ')"
        "Completed=$(Get-Date -Format o)"
    ) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $backupRoot 'deployment-result.txt')
    throw
}
