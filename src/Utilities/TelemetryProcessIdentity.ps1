function Get-TelemetryScriptProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $fullScriptPath = [IO.Path]::GetFullPath($ScriptPath)
    $escapedScriptPath = [regex]::Escape($fullScriptPath)
    $commandPattern = (
        '^\s*(?:"[^"]*\\powershell\.exe"|[^\s"]*\\powershell\.exe)\s+' +
        '-NoProfile\s+-ExecutionPolicy\s+Bypass' +
        '(?:\s+-WindowStyle\s+Hidden)?\s+' +
        '-File\s+(?:"{0}"|{0})(?:\s+.*)?$'
    ) -f $escapedScriptPath

    @(
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" `
            -OperationTimeoutSec 3 -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -match $commandPattern
            }
    )
}

function Stop-TelemetryScriptProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Process
    )

    process {
        try {
            Invoke-CimMethod -InputObject $Process -MethodName Terminate -ErrorAction Stop | Out-Null
            $true
        }
        catch {
            $false
        }
    }
}
