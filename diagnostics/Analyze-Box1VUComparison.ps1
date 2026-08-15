[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CaptureDirectory,

    [ValidateRange(1, 300)]
    [double]$MaximumOffsetSeconds = 30
)

$ErrorActionPreference = 'Stop'

$AnalysisScript = Join-Path $PSScriptRoot 'Analyze-Box1VUComparison.py'
$BundledPython = 'C:\Users\timmeh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'

if (-not (Test-Path -LiteralPath $AnalysisScript -PathType Leaf)) {
    throw "Analysis script not found: $AnalysisScript"
}

if (Test-Path -LiteralPath $BundledPython -PathType Leaf) {
    $maximumOffset = $MaximumOffsetSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
    & $BundledPython $AnalysisScript $CaptureDirectory `
        --maximum-offset-seconds $maximumOffset
}
else {
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -eq $python) {
        throw 'No Python runtime was found. The bundled Codex Python runtime is not present.'
    }
    $maximumOffset = $MaximumOffsetSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
    & $python.Source $AnalysisScript $CaptureDirectory `
        --maximum-offset-seconds $maximumOffset
}

if ($LASTEXITCODE -ne 0) {
    throw "Box 1 VU comparison analysis failed with exit code $LASTEXITCODE."
}
