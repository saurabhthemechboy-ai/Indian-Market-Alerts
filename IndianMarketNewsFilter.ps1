param(
    [string]$File,
    [int]$MinScore = 3,
    [switch]$Json
)

$HighImpactKeywords = [ordered]@{
    "rbi" = 3
    "repo rate" = 3
    "rate cut" = 3
    "rate hike" = 3
    "inflation" = 3
    "cpi" = 3
    "wpi" = 2
    "gdp" = 3
    "fii" = 3
    "dii" = 2
    "foreign institutional" = 3
    "crude" = 3
    "brent" = 3
    "oil price" = 3
    "rupee" = 3
    "usd/inr" = 3
    "dollar index" = 2
    "us fed" = 3
    "federal reserve" = 3
    "bond yield" = 2
    "geopolitical" = 2
    "west asia" = 3
    "iran" = 2
    "israel" = 2
    "china" = 2
    "tariff" = 2
    "budget" = 3
    "gst" = 2
    "sebi" = 2
    "election" = 3
    "monsoon" = 2
    "earnings" = 2
    "results" = 2
    "profit" = 2
    "above estimates" = 2
    "below estimates" = 2
    "capex" = 2
    "order win" = 2
    "government announces" = 2
}

$SectorKeywords = [ordered]@{
    "Bank Nifty / Financials" = @("bank", "nbfc", "hdfc bank", "icici", "sbi", "axis bank", "kotak", "credit growth", "npa", "repo rate")
    "IT" = @("it stocks", "software", "nasdaq", "tcs", "infosys", "wipro", "hcltech", "tech mahindra", "dollar")
    "Oil & Gas" = @("crude", "brent", "oil", "ongc", "reliance", "bpcl", "hpcl", "ioc", "gas")
    "Auto" = @("auto", "vehicle", "ev", "maruti", "mahindra", "tata motors", "bajaj auto", "eicher", "sales volume")
    "FMCG / Consumption" = @("fmcg", "rural demand", "monsoon", "hindustan unilever", "itc", "nestle", "dabur", "britannia")
    "Metals" = @("metal", "steel", "aluminium", "copper", "iron ore", "tata steel", "jsw steel", "hindalco", "vedanta")
    "Realty" = @("real estate", "realty", "housing", "home loan", "dlf", "godrej properties", "prestige", "sobha")
    "Infrastructure / Capital Goods" = @("infra", "infrastructure", "railway", "defence", "capital goods", "larsen", "l&t", "order win", "capex")
    "Pharma / Healthcare" = @("pharma", "usfda", "drug approval", "sun pharma", "cipla", "dr reddy", "apollo hospitals")
}

$BullishPatterns = @(
    "rate cut", "inflation eases", "crude falls", "oil prices drop", "rupee strengthens",
    "fii inflow", "fii buying", "profit rises", "beats estimates", "above estimates", "order win",
    "gst cut", "stimulus", "record high"
)

$BearishPatterns = @(
    "rate hike", "inflation rises", "crude surges", "oil prices rise", "rupee weakens",
    "record low", "fii outflow", "fii selling", "profit falls", "misses estimates", "below estimates",
    "downgrade", "default", "fraud", "war", "sanction"
)

$IgnorePatterns = @(
    "launches campaign", "brand ambassador", "awareness drive", "wins award",
    "appoints celebrity", "social media buzz"
)

function Test-Phrase {
    param(
        [string]$Text,
        [string]$Phrase
    )

    return $Text -match "\b$([regex]::Escape($Phrase))\b"
}

function Get-Direction {
    param([string]$Text)

    $bullish = 0
    $bearish = 0

    foreach ($pattern in $BullishPatterns) {
        if (Test-Phrase $Text $pattern) { $bullish += 1 }
    }
    foreach ($pattern in $BearishPatterns) {
        if (Test-Phrase $Text $pattern) { $bearish += 1 }
    }

    if ($bullish -gt $bearish) { return "Bullish" }
    if ($bearish -gt $bullish) { return "Bearish" }
    if (($bullish -gt 0) -and ($bearish -gt 0)) { return "Mixed" }
    return "Neutral"
}

function Get-Impact {
    param([int]$Score)

    if ($Score -ge 6) { return "High" }
    if ($Score -ge 3) { return "Medium" }
    return "Low"
}

function Get-Sectors {
    param([string]$Text)

    $sectors = New-Object System.Collections.Generic.List[string]
    foreach ($sector in $SectorKeywords.Keys) {
        foreach ($keyword in $SectorKeywords[$sector]) {
            if (Test-Phrase $Text $keyword) {
                $sectors.Add($sector)
                break
            }
        }
    }

    if ($sectors.Count -eq 0) { $sectors.Add("Broad Market") }
    return $sectors
}

function Get-NewsSignal {
    param([string]$Item)

    $text = ($Item.Trim() -replace "\s+", " ").ToLowerInvariant()

    foreach ($pattern in $IgnorePatterns) {
        if (Test-Phrase $text $pattern) {
            return [pscustomobject]@{
                Impact = "Low"
                Direction = "Neutral"
                Score = 0
                Affected = "Ignore"
                News = $Item
                Reason = "Promotional or low financial-impact wording."
            }
        }
    }

    $score = 0
    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($keyword in $HighImpactKeywords.Keys) {
        if (Test-Phrase $text $keyword) {
            $score += $HighImpactKeywords[$keyword]
            $matches.Add($keyword)
        }
    }

    $sectors = Get-Sectors $text
    $direction = Get-Direction $text

    if (-not ($sectors.Count -eq 1 -and $sectors[0] -eq "Broad Market")) {
        $score += 1
    }

    if (@("Bullish", "Bearish", "Mixed") -contains $direction) {
        $score += 1
    }

    $reasonParts = New-Object System.Collections.Generic.List[string]
    if ($matches.Count -gt 0) {
        $reasonParts.Add("Matched macro/market drivers: " + (($matches | Select-Object -First 5) -join ", "))
    }
    if (-not ($sectors.Count -eq 1 -and $sectors[0] -eq "Broad Market")) {
        $reasonParts.Add("Sector relevance: " + (($sectors | Select-Object -First 3) -join ", "))
    }
    if ($reasonParts.Count -eq 0) {
        $reasonParts.Add("No major market-moving driver detected.")
    }

    return [pscustomobject]@{
        Impact = Get-Impact $score
        Direction = $direction
        Score = $score
        Affected = $sectors -join ", "
        News = $Item
        Reason = $reasonParts -join " "
    }
}

if ($File) {
    $items = Get-Content -LiteralPath $File | Where-Object { $_.Trim().Length -gt 0 }
}
else {
    $rawInput = @($input)
    if ($rawInput.Count -gt 0) {
        $items = $rawInput | Where-Object { $_.Trim().Length -gt 0 }
    }
    else {
        $items = @((Read-Host "Paste one headline/news item"))
    }
}

$signals = foreach ($item in $items) {
    Get-NewsSignal $item
}

$signals = $signals |
    Where-Object { $_.Score -ge $MinScore } |
    Sort-Object -Property Score -Descending

if ($Json) {
    $signals | ConvertTo-Json -Depth 4
}
elseif ($signals.Count -eq 0) {
    "No market-moving news crossed the selected threshold."
}
else {
    $signals | Format-Table -AutoSize
}
