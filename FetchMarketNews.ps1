param(
    [string]$FeedsFile = ".\feeds.json",
    [string]$OutputJson = ".\market_alerts.json",
    [string]$OutputMarkdown = ".\market_alerts.md",
    [int]$MinScore = 3,
    [int]$MaxItemsPerFeed = 20,
    [switch]$SendTelegram,
    [int]$TelegramMinScore = 6,
    [int]$TelegramMaxAlerts = 5
)

$ErrorActionPreference = "Stop"

function Resolve-PathOrDefault {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return Join-Path (Get-Location) $PathValue
}

function Get-RssItems {
    param(
        [string]$FeedName,
        [string]$Url,
        [int]$Limit
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20
        [xml]$xml = $response.Content
    }
    catch {
        Write-Warning "Failed to fetch '$FeedName': $($_.Exception.Message)"
        return @()
    }

    $items = @()
    foreach ($item in ($xml.rss.channel.item | Select-Object -First $Limit)) {
        $title = [System.Net.WebUtility]::HtmlDecode([string]$item.title)
        $link = [string]$item.link
        $published = [string]$item.pubDate

        if ($title.Trim().Length -eq 0) {
            continue
        }

        $items += [pscustomobject]@{
            Feed = $FeedName
            Title = $title
            Link = $link
            Published = $published
        }
    }

    return $items
}

function Convert-ToMarkdown {
    param([object[]]$Alerts)

    if ($Alerts.Count -eq 0) {
        return "# Indian Market Alerts`n`nNo market-moving news crossed the selected threshold."
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Indian Market Alerts")
    $lines.Add("")
    $lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $lines.Add("")
    $lines.Add("| Impact | Direction | Score | Affected | News | Source |")
    $lines.Add("|---|---:|---:|---|---|---|")

    foreach ($alert in $Alerts) {
        $news = ([string]$alert.News).Replace("|", "\|")
        $affected = ([string]$alert.Affected).Replace("|", "\|")
        $source = ([string]$alert.Feed).Replace("|", "\|")
        if ($alert.Link) {
            $source = "[$source]($($alert.Link))"
        }

        $lines.Add("| $($alert.Impact) | $($alert.Direction) | $($alert.Score) | $affected | $news | $source |")
    }

    return $lines -join "`n"
}

function Expand-ScoredSignals {
    param([object[]]$Signals)

    $expanded = New-Object System.Collections.Generic.List[object]

    foreach ($signal in $Signals) {
        if ($signal.News -is [array]) {
            for ($index = 0; $index -lt $signal.News.Count; $index += 1) {
                $expanded.Add([pscustomobject]@{
                    Impact = $signal.Impact[$index]
                    Direction = $signal.Direction[$index]
                    Score = $signal.Score[$index]
                    Affected = $signal.Affected[$index]
                    News = $signal.News[$index]
                    Reason = $signal.Reason[$index]
                })
            }
        }
        else {
            $expanded.Add($signal)
        }
    }

    return $expanded
}

function Get-PowerShellCommand {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return "pwsh"
    }
    return "powershell"
}

$feedsPath = Resolve-PathOrDefault $FeedsFile
$outputJsonPath = Resolve-PathOrDefault $OutputJson
$outputMarkdownPath = Resolve-PathOrDefault $OutputMarkdown

if (-not (Test-Path -LiteralPath $feedsPath)) {
    throw "Feeds file not found: $feedsPath"
}

$feeds = Get-Content -LiteralPath $feedsPath -Raw | ConvertFrom-Json
$rssItems = New-Object System.Collections.Generic.List[object]

foreach ($feed in $feeds) {
    $items = Get-RssItems -FeedName $feed.name -Url $feed.url -Limit $MaxItemsPerFeed
    foreach ($item in $items) {
        $rssItems.Add($item)
    }
}

$deduped = @($rssItems.ToArray()) |
    Group-Object -Property Title |
    ForEach-Object { $_.Group | Select-Object -First 1 }

if ($deduped.Count -eq 0) {
    $empty = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("o")
        MinScore = $MinScore
        Alerts = @()
        Errors = "No RSS items fetched. Check internet access or feed URLs."
    }
    $empty | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputJsonPath -Encoding UTF8
    Convert-ToMarkdown -Alerts @() | Set-Content -LiteralPath $outputMarkdownPath -Encoding UTF8
    Write-Output "No RSS items fetched. Wrote empty alert files."
    exit 0
}

$tempHeadlines = Join-Path ([System.IO.Path]::GetTempPath()) ("market-headlines-" + [guid]::NewGuid().ToString() + ".txt")
$deduped.Title | Set-Content -LiteralPath $tempHeadlines -Encoding UTF8

try {
    $powerShellCommand = Get-PowerShellCommand
    $scoredJson = & $powerShellCommand -ExecutionPolicy Bypass -File ".\IndianMarketNewsFilter.ps1" -File $tempHeadlines -MinScore $MinScore -Json
}
finally {
    Remove-Item -LiteralPath $tempHeadlines -Force -ErrorAction SilentlyContinue
}

$scoredText = ($scoredJson -join "`n").Trim()

if (-not $scoredText) {
    $scored = @()
}
else {
    $scored = @($scoredText | ConvertFrom-Json)
}

$scored = @(Expand-ScoredSignals -Signals $scored)

$lookup = @{}
foreach ($item in $deduped) {
    $lookup[$item.Title] = $item
}

$alerts = foreach ($signal in $scored) {
    $source = $lookup[$signal.News]
    [pscustomobject]@{
        Impact = $signal.Impact
        Direction = $signal.Direction
        Score = $signal.Score
        Affected = $signal.Affected
        News = $signal.News
        Reason = $signal.Reason
        Feed = $source.Feed
        Link = $source.Link
        Published = $source.Published
    }
}

$report = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString("o")
    MinScore = $MinScore
    TotalFetched = $rssItems.Count
    TotalUnique = @($deduped).Count
    TotalAlerts = @($alerts).Count
    Alerts = @($alerts)
}

$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputJsonPath -Encoding UTF8
Convert-ToMarkdown -Alerts @($alerts) | Set-Content -LiteralPath $outputMarkdownPath -Encoding UTF8

Write-Output "Fetched $($rssItems.Count) RSS items, found $(@($alerts).Count) market alerts."
Write-Output "JSON: $outputJsonPath"
Write-Output "Markdown: $outputMarkdownPath"

if ($SendTelegram) {
    $powerShellCommand = Get-PowerShellCommand
    & $powerShellCommand -ExecutionPolicy Bypass -File ".\SendTelegramAlerts.ps1" `
        -AlertsFile $outputJsonPath `
        -MinScore $TelegramMinScore `
        -MaxAlerts $TelegramMaxAlerts
}
