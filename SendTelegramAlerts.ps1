param(
    [string]$AlertsFile = ".\market_alerts.json",
    [string]$StateFile = ".\sent_alerts.json",
    [int]$MinScore = 6,
    [int]$MaxAlerts = 5,
    [int]$StateDays = 7,
    [switch]$DryRun,
    [switch]$ResetState,
    [switch]$IncludeAlreadySent
)

$ErrorActionPreference = "Stop"

function Resolve-PathOrDefault {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return Join-Path (Get-Location) $PathValue
}

function ConvertTo-TelegramMessage {
    param([object]$Alert)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("<b>Indian Market Alert</b>")
    $lines.Add("Format: NO_LINK_V2")
    $lines.Add("$(ConvertTo-HtmlText $Alert.Impact) | $(ConvertTo-HtmlText $Alert.Direction) | Score $(ConvertTo-HtmlText $Alert.Score)")
    $lines.Add("Affected: $(ConvertTo-HtmlText $Alert.Affected)")
    $lines.Add("")
    $lines.Add("$(ConvertTo-HtmlText $Alert.News)")
    if ($Alert.Reason) {
        $lines.Add("")
        $lines.Add("Reason: $(ConvertTo-HtmlText $Alert.Reason)")
    }

    return ($lines -join "`n").Trim()
}

function ConvertTo-HtmlText {
    param([object]$Value)

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-HtmlAttribute {
    param([object]$Value)

    return ([System.Net.WebUtility]::HtmlEncode([string]$Value)).Replace("'", "&#39;")
}

function Send-TelegramMessage {
    param(
        [string]$BotToken,
        [string]$ChatId,
        [string]$Message
    )

    $uri = "https://api.telegram.org/bot$BotToken/sendMessage"
    $body = @{
        chat_id = $ChatId
        text = $Message
        parse_mode = "HTML"
        disable_web_page_preview = $true
    }

    Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 20 | Out-Null
}

function Get-AlertKey {
    param([object]$Alert)

    if ($Alert.Link) {
        return "link:$($Alert.Link)"
    }

    $normalized = ([string]$Alert.News).Trim().ToLowerInvariant() -replace "\s+", " "
    return "news:$normalized"
}

function Read-SentState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{}
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if (-not $raw.Trim()) {
        return @{}
    }

    $data = $raw | ConvertFrom-Json
    $state = @{}
    foreach ($entry in @($data.SentAlerts)) {
        if ($entry.Key) {
            $state[$entry.Key] = $entry.SentAt
        }
    }

    return $state
}

function Write-SentState {
    param(
        [string]$Path,
        [hashtable]$State,
        [int]$KeepDays
    )

    $cutoff = (Get-Date).AddDays(-1 * $KeepDays)
    $entries = foreach ($key in $State.Keys) {
        $sentAt = [datetime]$State[$key]
        if ($sentAt -ge $cutoff) {
            [pscustomobject]@{
                Key = $key
                SentAt = $sentAt.ToString("o")
            }
        }
    }

    $payload = [pscustomobject]@{
        UpdatedAt = (Get-Date).ToString("o")
        StateDays = $KeepDays
        SentAlerts = @($entries | Sort-Object -Property SentAt -Descending)
    }

    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$alertsPath = Resolve-PathOrDefault $AlertsFile
$statePath = Resolve-PathOrDefault $StateFile

if (-not (Test-Path -LiteralPath $alertsPath)) {
    throw "Alerts file not found: $alertsPath"
}

if ($ResetState -and (Test-Path -LiteralPath $statePath)) {
    Remove-Item -LiteralPath $statePath -Force
}

$report = Get-Content -LiteralPath $alertsPath -Raw | ConvertFrom-Json
$sentState = Read-SentState -Path $statePath

Write-Output "Telegram format version: NO_LINK_V2"

$alerts = @($report.Alerts) |
    Where-Object { [int]$_.Score -ge $MinScore } |
    Where-Object { $IncludeAlreadySent -or -not $sentState.ContainsKey((Get-AlertKey -Alert $_)) } |
    Sort-Object -Property Score -Descending |
    Select-Object -First $MaxAlerts

if ($alerts.Count -eq 0) {
    Write-Output "No Telegram alerts crossed MinScore $MinScore."
    exit 0
}

if ($DryRun) {
    foreach ($alert in $alerts) {
        ConvertTo-TelegramMessage -Alert $alert
        ""
        "---"
        ""
    }
    exit 0
}

$botToken = $env:TELEGRAM_BOT_TOKEN
if (-not $botToken) {
    $botToken = $env:TELEGRAM_TOKEN
}
$chatId = $env:TELEGRAM_CHAT_ID

if (-not $botToken -or -not $chatId) {
    throw "Set TELEGRAM_BOT_TOKEN or TELEGRAM_TOKEN, plus TELEGRAM_CHAT_ID, before sending."
}

foreach ($alert in $alerts) {
    $message = ConvertTo-TelegramMessage -Alert $alert
    Send-TelegramMessage -BotToken $botToken -ChatId $chatId -Message $message
    $sentState[(Get-AlertKey -Alert $alert)] = (Get-Date).ToString("o")
}

Write-SentState -Path $statePath -State $sentState -KeepDays $StateDays
Write-Output "Sent $($alerts.Count) Telegram alert(s)."
