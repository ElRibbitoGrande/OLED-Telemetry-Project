$ErrorActionPreference = "Stop"

$inputDir = "C:\ChatGPT-Export\Extracted"
$outputDir = "C:\OLED-Telemetry-Project\docs\chat-archive"

$conversationFiles = @(
    Get-ChildItem -Path $inputDir -Filter "conversations-*.json" -File |
    Sort-Object Name
)

if ($conversationFiles.Count -eq 0) {
    throw "Could not find any conversations-*.json files in: $inputDir"
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# Terms likely to identify OLED-project conversations.
$searchTerms = @(
    "OLED",
    "Telemetry",
    "Rainmeter",
    "denon_status",
    "Analog_Floating",
    "NowPlayingRouter",
    "DecoderCollector",
    "TelemetryManager",
    "WiiM collector",
    "album artwork",
    "OLED Shift"
)

$conversations = New-Object System.Collections.Generic.List[object]

foreach ($file in $conversationFiles) {
    Write-Host "Loading $($file.Name)..."
    $fileConversations = Get-Content $file.FullName -Raw | ConvertFrom-Json

    foreach ($conversation in $fileConversations) {
        $conversations.Add($conversation)
    }
}

Write-Host ""
Write-Host "Loaded $($conversations.Count) conversations from $($conversationFiles.Count) files."

function Get-ConversationText {
    param($Conversation)

    $parts = New-Object System.Collections.Generic.List[string]

    if ($Conversation.title) {
        $parts.Add([string]$Conversation.title)
    }

    if ($Conversation.mapping) {
        foreach ($property in $Conversation.mapping.PSObject.Properties) {
            $node = $property.Value

            if (
                $node.message -and
                $node.message.content -and
                $node.message.content.parts
            ) {
                foreach ($part in $node.message.content.parts) {
                    if ($part -is [string]) {
                        $parts.Add($part)
                    }
                }
            }
        }
    }

    return ($parts -join "`n")
}

function ConvertTo-SafeFilename {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = "Untitled Conversation"
    }

    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $Name = $Name.Replace($char, "_")
    }

    $Name = $Name.Trim()

    if ($Name.Length -gt 100) {
        $Name = $Name.Substring(0, 100)
    }

    return $Name
}

$results = @()

foreach ($conversation in $conversations) {
    $allText = Get-ConversationText -Conversation $conversation

    $matchedTerms = @(
        $searchTerms | Where-Object {
            $allText -match [regex]::Escape($_)
        }
    )

    if ($matchedTerms.Count -gt 0) {
        $results += [pscustomobject]@{
            Conversation = $conversation
            Title        = $conversation.title
            MatchedTerms = $matchedTerms
            FullText     = $allText
        }
    }
}

Write-Host ""
Write-Host "Found $($results.Count) possible OLED-related conversations:"
Write-Host ""

for ($i = 0; $i -lt $results.Count; $i++) {
    $number = $i + 1
    $title = $results[$i].Title
    $terms = $results[$i].MatchedTerms -join ", "

    Write-Host "[$number] $title"
    Write-Host "    Matched: $terms"
}

Write-Host ""
$selection = Read-Host "Enter numbers to export, separated by commas, or type ALL"

if ($selection.Trim().ToUpperInvariant() -eq "ALL") {
    $selectedIndexes = 0..($results.Count - 1)
}
else {
    $selectedIndexes = @()

    foreach ($item in $selection -split ",") {
        $trimmed = $item.Trim()

        if ($trimmed -notmatch '^\d+$') {
            Write-Warning "Skipping invalid selection: $trimmed"
            continue
        }

        $index = [int]$trimmed - 1

        if ($index -lt 0 -or $index -ge $results.Count) {
            Write-Warning "Selection out of range: $trimmed"
            continue
        }

        $selectedIndexes += $index
    }
}

if ($selectedIndexes.Count -eq 0) {
    throw "No conversations selected."
}

$counter = 1

foreach ($index in $selectedIndexes) {
    $match = $results[$index]
    $conversation = $match.Conversation

    $safeTitle = ConvertTo-SafeFilename -Name $conversation.title
    $filename = "{0:D2}-{1}.md" -f $counter, $safeTitle
    $outputFile = Join-Path $outputDir $filename

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("# $($conversation.title)")
    $lines.Add("")
    $lines.Add("Matched search terms: $($match.MatchedTerms -join ', ')")
    $lines.Add("")

    $messages = @()

    foreach ($property in $conversation.mapping.PSObject.Properties) {
        $node = $property.Value

        if (-not $node.message) {
            continue
        }

        $message = $node.message
        $role = $message.author.role
        $createTime = $message.create_time

        $messageParts = @()

        if ($message.content -and $message.content.parts) {
            foreach ($part in $message.content.parts) {
                if ($part -is [string] -and -not [string]::IsNullOrWhiteSpace($part)) {
                    $messageParts += $part
                }
            }
        }

        if ($messageParts.Count -eq 0) {
            continue
        }

        $messages += [pscustomobject]@{
            Role       = $role
            CreateTime = $createTime
            Text       = ($messageParts -join "`n")
        }
    }

    $messages = $messages | Sort-Object {
        if ($null -eq $_.CreateTime) {
            [double]::MaxValue
        }
        else {
            [double]$_.CreateTime
        }
    }

    foreach ($message in $messages) {
        $speaker = switch ($message.Role) {
            "user"      { "User" }
            "assistant" { "Assistant" }
            "system"    { "System" }
            default     { $message.Role }
        }

        $lines.Add("## $speaker")
        $lines.Add("")
        $lines.Add($message.Text)
        $lines.Add("")
    }

    Set-Content -Path $outputFile -Value $lines -Encoding UTF8

    Write-Host "Exported: $outputFile"
    $counter++
}

Write-Host ""
Write-Host "Finished exporting selected conversations."