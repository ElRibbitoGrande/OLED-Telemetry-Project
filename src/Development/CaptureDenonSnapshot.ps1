# Denon configuration snapshot tool
# Read-only: retrieves XML from the AVR and writes flattened reports.

$ip = "192.168.0.128"
$outDir = "C:\RainmeterDenon\Development\DenonSnapshots"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.ServerCertificateCustomValidationCallback = { $true }

$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(15)
$client.DefaultRequestHeaders.CacheControl =
    [System.Net.Http.Headers.CacheControlHeaderValue]::new()
$client.DefaultRequestHeaders.CacheControl.NoCache = $true
$client.DefaultRequestHeaders.CacheControl.NoStore = $true

function Get-NodePath {
    param([System.Xml.XmlNode]$Node)

    $parts = [System.Collections.Generic.List[string]]::new()
    $current = $Node

    while ($null -ne $current -and $current.NodeType -ne
        [System.Xml.XmlNodeType]::Document) {

        $name = $current.Name

        if ($null -ne $current.ParentNode) {
            $sameName = @(
                $current.ParentNode.ChildNodes |
                Where-Object { $_.Name -eq $current.Name }
            )

            if ($sameName.Count -gt 1) {
                $index = [array]::IndexOf($sameName, $current) + 1
                $name = "$name[$index]"
            }
        }

        $parts.Insert(0, $name)
        $current = $current.ParentNode
    }

    return "/" + ($parts -join "/")
}

function Convert-XmlToReport {
    param(
        [xml]$Xml,
        [string]$Endpoint
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Endpoint=$Endpoint")
    $lines.Add("Captured=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')")
    $lines.Add("")

    foreach ($node in $Xml.SelectNodes("//*")) {
        $elementChildren = @(
            $node.ChildNodes |
            Where-Object {
                $_.NodeType -eq [System.Xml.XmlNodeType]::Element
            }
        )

        if ($elementChildren.Count -eq 0) {
            $path = Get-NodePath $node
            $value = ([string]$node.InnerText).Trim()
            $lines.Add("$path=$value")
        }

        if ($node.Attributes) {
            foreach ($attribute in $node.Attributes) {
                $path = Get-NodePath $node
                $lines.Add("$path/@$($attribute.Name)=$($attribute.Value)")
            }
        }
    }

    return $lines
}

function Save-DenonEndpoint {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Label
    )

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $safeLabel = $Label -replace '[^\w\-]+', '_'
    $baseName = "${stamp}_${safeLabel}_${Name}"

    $xmlPath = Join-Path $outDir "$baseName.xml"
    $txtPath = Join-Path $outDir "$baseName.txt"

    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $separator = if ($Url.Contains("?")) { "&" } else { "?" }
    $requestUrl = "$Url$separator`_=$cacheBust"

    Write-Host "Reading $Name..." -ForegroundColor Cyan

    try {
        $raw = $client.GetStringAsync($requestUrl).GetAwaiter().GetResult()
        $raw | Set-Content -LiteralPath $xmlPath -Encoding UTF8

        $xml = [xml]$raw
        Convert-XmlToReport -Xml $xml -Endpoint $requestUrl |
            Set-Content -LiteralPath $txtPath -Encoding UTF8

        Write-Host "Saved: $txtPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "$Name failed: $($_.Exception.Message)"
    }
}

try {
    $label = Read-Host "Enter a label for this snapshot"

    Save-DenonEndpoint `
        -Name "Audyssey" `
        -Url "https://$ip`:10443/ajax/audio/get_config?type=9" `
        -Label $label

    Save-DenonEndpoint `
        -Name "Globals" `
        -Url "https://$ip`:10443/ajax/globals/get_config?type=10" `
        -Label $label

    Write-Host ""
    Write-Host "Snapshot complete." -ForegroundColor Green
    Write-Host "Files are in: $outDir"
}
finally {
    $client.Dispose()
    $handler.Dispose()
}
