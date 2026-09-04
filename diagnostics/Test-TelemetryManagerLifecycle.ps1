[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SourceRoot = Join-Path $RepositoryRoot 'src'
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'RainmeterDenon-TelemetryLifecycle-{0}' -f [guid]::NewGuid().ToString('N')
)
$ManagerMutexName = 'Local\RainmeterDenonTelemetryManagerTest_{0}' -f [guid]::NewGuid().ToString('N')
$ListenerMutexName = 'Local\RainmeterDenonRefreshHotkeyTest_{0}' -f [guid]::NewGuid().ToString('N')
$UnrelatedProcess = $null
$ProductionHotkeyPath = Join-Path $SourceRoot 'Utilities\RainmeterRefreshHotkey.ps1'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Output "PASS: $Message"
}

function Wait-Until {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [int]$TimeoutSeconds = 10,
        [string]$FailureMessage = 'Condition was not satisfied.'
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)

    throw "TIMEOUT: $FailureMessage"
}

function Write-TestFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-TestProcesses([string]$ScriptPath) {
    $result = @(Get-TelemetryScriptProcesses -ScriptPath $ScriptPath)
    Write-Output -NoEnumerate $result
}

function Start-TestManager {
    Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $ManagerPath),
        '-Root', ('"{0}"' -f $TestRoot),
        '-ManagerMutexName', ('"{0}"' -f $ManagerMutexName),
        '-SupervisionIntervalMilliseconds', '250',
        '-HotkeyRetrySeconds', '1'
    )
}

function Write-HealthyListener {
    Write-TestFile -Path $HotkeyPath -Content (@'
$createdNew = $false
$mutex = [Threading.Mutex]::new($true, '__MUTEX__', [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    exit 0
}
try {
    while ($true) { Start-Sleep -Milliseconds 250 }
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
'@).Replace('__MUTEX__', $ListenerMutexName)
}

New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

try {
    $productionHotkeyContent = [IO.File]::ReadAllText($ProductionHotkeyPath)
    Assert-True ($productionHotkeyContent -match '\$script:RefreshVirtualKey\s*=\s*\[uint32\]0x7A\s*# F11') `
        'production listener registers VK_F11'
    Assert-True ($productionHotkeyContent -match 'RefreshHotkey=Ctrl\+Alt\+F11') `
        'production listener logs the Ctrl+Alt+F11 chord'
    Assert-True ($productionHotkeyContent -match '\$script:DiagnosticVirtualKey\s*=\s*\[uint32\]0x79\s*# F10') `
        'production listener registers VK_F10 for artwork diagnostics'
    Assert-True ($productionHotkeyContent -match 'DiagnosticHotkey=Ctrl\+Alt\+F10') `
        'production listener logs the Ctrl+Alt+F10 diagnostic chord'
    Assert-True ($productionHotkeyContent -notmatch 'SetWindowsHookEx|WH_KEYBOARD_LL|InstallKeyboardFallback') `
        'production listener contains no low-level keyboard-hook fallback'

    New-Item -ItemType Directory -Path (Join-Path $TestRoot 'Utilities') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TestRoot 'NowPlaying') -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $SourceRoot 'TelemetryManager.ps1') -Destination $TestRoot
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'TelemetryProcessControl.ps1') -Destination $TestRoot
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'Utilities\TelemetryProcessIdentity.ps1') `
        -Destination (Join-Path $TestRoot 'Utilities')

    $ManagerPath = Join-Path $TestRoot 'TelemetryManager.ps1'
    $ControlPath = Join-Path $TestRoot 'TelemetryProcessControl.ps1'
    $fixtureNames = @{
        'denon_status.ps1' = 'FixtureDenon.ps1'
        'DecoderCollector.ps1' = 'FixtureDecoder.ps1'
        'Box1Collector.ps1' = 'FixtureBoxOne.ps1'
        'NowPlayingRouter.ps1' = 'FixtureRouter.ps1'
        'AppleMusicCollector.ps1' = 'FixtureApple.ps1'
        'WiiM-NowPlaying-Bridge.ps1' = 'FixtureWiiM.ps1'
        'RainmeterRefreshHotkey.ps1' = 'FixtureRefreshListener.ps1'
    }
    foreach ($path in @($ManagerPath, $ControlPath)) {
        $content = [IO.File]::ReadAllText($path)
        foreach ($replacement in $fixtureNames.GetEnumerator()) {
            $content = $content.Replace($replacement.Key, $replacement.Value)
        }
        [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
    }

    $HotkeyPath = Join-Path $TestRoot 'Utilities\FixtureRefreshListener.ps1'
    $IdentityPath = Join-Path $TestRoot 'Utilities\TelemetryProcessIdentity.ps1'
    $StatePath = Join-Path $TestRoot 'telemetry_manager_status.txt'
    $LogPath = Join-Path $TestRoot 'telemetry_manager.log'

    . $IdentityPath

    $collectorDefinitions = @(
        @{ Path = Join-Path $TestRoot 'FixtureDenon.ps1'; Heartbeat = Join-Path $TestRoot 'denon_heartbeat.txt' }
        @{ Path = Join-Path $TestRoot 'FixtureDecoder.ps1'; Heartbeat = Join-Path $TestRoot 'decoder_heartbeat.txt' }
        @{ Path = Join-Path $TestRoot 'FixtureBoxOne.ps1'; Heartbeat = Join-Path $TestRoot 'box1_heartbeat.txt' }
        @{ Path = Join-Path $TestRoot 'NowPlaying\FixtureRouter.ps1'; Heartbeat = Join-Path $TestRoot 'NowPlaying\router_heartbeat.txt' }
    )

    foreach ($definition in $collectorDefinitions) {
        $escapedHeartbeat = $definition.Heartbeat.Replace("'", "''")
        Write-TestFile -Path $definition.Path -Content (@'
while ($true) {
    Set-Content -LiteralPath '__HEARTBEAT__' -Value (Get-Date -Format 'o') -Encoding ASCII
    Start-Sleep -Milliseconds 250
}
'@).Replace('__HEARTBEAT__', $escapedHeartbeat)
    }

    Write-TestFile -Path (Join-Path $TestRoot 'NowPlaying\now_playing.txt') -Content 'Active=0'
    Write-HealthyListener

    $managerProcess = Start-TestManager
    Wait-Until -TimeoutSeconds 15 -FailureMessage 'Manager and listener did not start exactly once.' -Condition {
        (Get-TestProcesses $ManagerPath).Count -eq 1 -and
        (Get-TestProcesses $HotkeyPath).Count -eq 1
    }

    $listenerPID = [int](Get-TestProcesses $HotkeyPath)[0].ProcessId
    Start-Sleep -Seconds 2
    Assert-True ((Get-TestProcesses $HotkeyPath).Count -eq 1) 'healthy listener remains a single instance'
    Assert-True ([int](Get-TestProcesses $HotkeyPath)[0].ProcessId -eq $listenerPID) 'healthy listener is not relaunched'
    Assert-True (@(Select-String -LiteralPath $LogPath -SimpleMatch 'Healthy existing Rainmeter refresh hotkey listener detected.').Count -le 1) 'healthy listener detection is not repeatedly logged'

    $duplicate = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $HotkeyPath)
    )
    [void]$duplicate.WaitForExit(5000)
    Assert-True ($duplicate.HasExited) 'second listener is rejected by duplicate prevention'
    Assert-True ((Get-TestProcesses $HotkeyPath).Count -eq 1) 'exactly one listener remains after duplicate attempt'
    Assert-True ([int](Get-TestProcesses $HotkeyPath)[0].ProcessId -eq $listenerPID) 'duplicate attempt preserves original listener'
    $duplicate.Dispose()

    [void](Stop-TelemetryScriptProcess -Process (Get-TestProcesses $HotkeyPath)[0])
    Wait-Until -TimeoutSeconds 10 -FailureMessage 'Manager did not restore the listener.' -Condition {
        $matches = Get-TestProcesses $HotkeyPath
        $matches.Count -eq 1 -and [int]$matches[0].ProcessId -ne $listenerPID
    }
    Start-Sleep -Milliseconds 500
    $recoveredPID = [int](Get-TestProcesses $HotkeyPath)[0].ProcessId
    Assert-True ($recoveredPID -ne $listenerPID) 'killed listener is restored with a new PID'
    Assert-True ((Get-TestProcesses $ManagerPath).Count -eq 1) 'manager remains alive after listener recovery'

    Write-TestFile -Path $HotkeyPath -Content 'exit 17'
    [void](Stop-TelemetryScriptProcess -Process (Get-TestProcesses $HotkeyPath)[0])
    Wait-Until -TimeoutSeconds 8 -FailureMessage 'Immediate listener exit was not logged.' -Condition {
        (Test-Path -LiteralPath $LogPath) -and
        (Select-String -LiteralPath $LogPath -SimpleMatch 'ExitCode=17' -Quiet)
    }
    Assert-True ((Get-TestProcesses $ManagerPath).Count -eq 1) 'listener immediate exit does not terminate manager'
    Assert-True ((Get-TestProcesses $HotkeyPath).Count -eq 0) 'immediate-exit listener does not persist'

    Move-Item -LiteralPath $HotkeyPath -Destination "$HotkeyPath.missing"
    Wait-Until -TimeoutSeconds 10 -FailureMessage 'Missing listener script was not logged.' -Condition {
        (Select-String -LiteralPath $LogPath -SimpleMatch 'script not found' -Quiet)
    }
    Assert-True ((Get-TestProcesses $ManagerPath).Count -eq 1) 'missing listener script does not terminate manager'
    Assert-True ((Select-String -LiteralPath $LogPath -SimpleMatch 'script not found' -Quiet)) 'missing listener script is distinguished in the log'

    Move-Item -LiteralPath "$HotkeyPath.missing" -Destination $HotkeyPath
    Write-HealthyListener
    Wait-Until -TimeoutSeconds 10 -FailureMessage 'Listener did not recover after startup failure was removed.' -Condition {
        (Get-TestProcesses $HotkeyPath).Count -eq 1
    }

    $lockStream = [IO.File]::Open($StatePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $directWriteFailed = $false
        try {
            [IO.File]::WriteAllLines($StatePath, @('Manager=Running'))
        }
        catch [IO.IOException] {
            $directWriteFailed = $true
        }
        Assert-True $directWriteFailed 'old direct status overwrite fails under a transient exclusive reader'
        Start-Sleep -Seconds 2
        Assert-True ((Get-TestProcesses $ManagerPath).Count -eq 1) 'status-file lock does not terminate corrected manager'
    }
    finally {
        $lockStream.Dispose()
    }

    Wait-Until -TimeoutSeconds 8 -FailureMessage 'Status did not recover after lock release.' -Condition {
        (Get-Content -LiteralPath $StatePath -ErrorAction SilentlyContinue) -contains 'Manager=Running'
    }

    $unrelatedCommand = "Start-Sleep -Seconds 30 # $ManagerPath $HotkeyPath"
    $UnrelatedProcess = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-Command', ('"{0}"' -f $unrelatedCommand)
    )
    Start-Sleep -Milliseconds 500

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ControlPath -Action Stop -Root $TestRoot
    Wait-Until -TimeoutSeconds 10 -FailureMessage 'Exact telemetry processes did not stop.' -Condition {
        (Get-TestProcesses $ManagerPath).Count -eq 0 -and
        (Get-TestProcesses $HotkeyPath).Count -eq 0
    }
    $UnrelatedProcess.Refresh()
    Assert-True (-not $UnrelatedProcess.HasExited) 'stop control preserves unrelated PowerShell command containing telemetry paths'
    Assert-True ((Get-Content -LiteralPath $StatePath) -contains 'Manager=Stopped') 'stop control marks manager status stopped'

    $launcherPath = Join-Path $TestRoot 'LaunchTelemetryManager.vbs'
    $managerCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{0}"" -Root ""{1}"" -ManagerMutexName ""{2}"" -SupervisionIntervalMilliseconds 250 -HotkeyRetrySeconds 1' -f $ManagerPath, $TestRoot, $ManagerMutexName
    Write-TestFile -Path $launcherPath -Content (
        'CreateObject("WScript.Shell").Run "{0}", 0, False' -f $managerCommand
    )

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ControlPath `
        -Action Restart -Root $TestRoot -LauncherPath $launcherPath
    Wait-Until -TimeoutSeconds 15 -FailureMessage 'Restart did not create exactly one manager and listener.' -Condition {
        (Get-TestProcesses $ManagerPath).Count -eq 1 -and
        (Get-TestProcesses $HotkeyPath).Count -eq 1
    }
    Assert-True ((Get-TestProcesses $ManagerPath).Count -eq 1) 'restart creates exactly one manager'
    Assert-True ((Get-TestProcesses $HotkeyPath).Count -eq 1) 'restart creates exactly one listener'

    $listenerProcess = Get-Process -Id ([int](Get-TestProcesses $HotkeyPath)[0].ProcessId) -ErrorAction Stop
    Assert-True ($listenerProcess.MainWindowHandle -eq 0) 'listener has no visible main window'

    Write-Output 'ALL ISOLATED TELEMETRY LIFECYCLE TESTS PASSED'
}
catch {
    Write-Output "TEST FAILURE ROOT: $TestRoot"
    if (Test-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue) {
        Write-Output '===== FIXTURE MANAGER LOG ====='
        Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue
    }
    Write-Output '===== FIXTURE PROCESS SNAPSHOT ====='
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$TestRoot*" } |
        Select-Object ProcessId, ParentProcessId, CommandLine |
        Format-List
    throw
}
finally {
    if (Test-Path -LiteralPath (Join-Path $TestRoot 'TelemetryProcessControl.ps1')) {
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                -File (Join-Path $TestRoot 'TelemetryProcessControl.ps1') -Action Stop -Root $TestRoot
        }
        catch {}
    }

    if ($null -ne $UnrelatedProcess) {
        try {
            $UnrelatedProcess.Refresh()
            if (-not $UnrelatedProcess.HasExited) { $UnrelatedProcess.Kill() }
            $UnrelatedProcess.Dispose()
        }
        catch {}
    }

    $resolvedTemp = [IO.Path]::GetFullPath($TestRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp) -like 'RainmeterDenon-TelemetryLifecycle-*') {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
