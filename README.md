# Indian Market News Filter

A small rule-based AI-agent starter for filtering news that may affect Indian share markets.

It scores each news item by likely market relevance, labels the direction, and maps it to affected sectors such as Bank Nifty, IT, Oil & Gas, FMCG, Metals, Realty, Infrastructure, and Pharma.

This is an informational screening tool, not investment advice.

## Run on Windows PowerShell

```powershell
.\IndianMarketNewsFilter.ps1 -File .\sample_news.txt
```

If script execution is blocked on your machine, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\IndianMarketNewsFilter.ps1 -File .\sample_news.txt
```

JSON output:

```powershell
powershell -ExecutionPolicy Bypass -File .\IndianMarketNewsFilter.ps1 -File .\sample_news.txt -Json
```

## Fetch Live RSS Alerts

```powershell
powershell -ExecutionPolicy Bypass -File .\FetchMarketNews.ps1
```

This reads RSS sources from `feeds.json`, filters the headlines, and writes:

- `market_alerts.json`
- `market_alerts.md`

To make the filter stricter:

```powershell
powershell -ExecutionPolicy Bypass -File .\FetchMarketNews.ps1 -MinScore 6
```

## Send Telegram Alerts

Create a Telegram bot using `@BotFather`, then get your chat ID. Set these environment variables in PowerShell:

```powershell
$env:TELEGRAM_BOT_TOKEN="your_bot_token"
$env:TELEGRAM_CHAT_ID="your_chat_id"
```

`TELEGRAM_TOKEN` also works as an alias for `TELEGRAM_BOT_TOKEN`.

Preview the message before sending:

```powershell
powershell -ExecutionPolicy Bypass -File .\SendTelegramAlerts.ps1 -DryRun
```

Send alerts from the latest `market_alerts.json`:

```powershell
powershell -ExecutionPolicy Bypass -File .\SendTelegramAlerts.ps1
```

Fetch live RSS news and send high-impact Telegram alerts in one command:

```powershell
powershell -ExecutionPolicy Bypass -File .\FetchMarketNews.ps1 -SendTelegram
```

By default, Telegram sends only alerts with score `6+`, up to 5 alerts. You can change that:

```powershell
powershell -ExecutionPolicy Bypass -File .\FetchMarketNews.ps1 -SendTelegram -TelegramMinScore 8 -TelegramMaxAlerts 3
```

Telegram deduplication is automatic. Sent alert keys are stored in `sent_alerts.json` for 7 days so repeated runs do not spam the same headline.

Reset the dedupe memory:

```powershell
powershell -ExecutionPolicy Bypass -File .\SendTelegramAlerts.ps1 -ResetState -DryRun
```

Send even if the alert was already sent:

```powershell
powershell -ExecutionPolicy Bypass -File .\SendTelegramAlerts.ps1 -IncludeAlreadySent
```

## Run on GitHub Actions

Add these repository secrets in GitHub:

- `TELEGRAM_CHAT_ID`
- `TELEGRAM_TOKEN`

Then commit and push this project, including:

- `.github/workflows/market-alerts.yml`
- `FetchMarketNews.ps1`
- `SendTelegramAlerts.ps1`
- `IndianMarketNewsFilter.ps1`
- `feeds.json`

The workflow runs:

- 08:30 IST, Monday-Friday
- Hourly from 09:15 to 15:15 IST, Monday-Friday

You can also run it manually from GitHub:

`Actions` -> `Indian Market Alerts` -> `Run workflow`

## Run with Python

```powershell
python .\indian_market_news_filter.py --file .\sample_news.txt
```

Or paste headlines through stdin:

```powershell
Get-Content .\sample_news.txt | python .\indian_market_news_filter.py
```

Python JSON output:

```powershell
python .\indian_market_news_filter.py --file .\sample_news.txt --json
```

## Scoring

- `6+`: High impact
- `3-5`: Medium impact
- `<3`: Low impact and hidden by default

Default filter threshold is `--min-score 3`.

Examples of high-signal triggers:

- RBI policy, repo rate, inflation, GDP
- Crude oil, Brent, rupee, USD/INR
- FII/DII flows
- US Fed, dollar index, bond yields
- Budget, GST, tariffs, elections
- Earnings beats/misses and major sector policy

## Next Useful Additions

- Connect live RSS/news sources.
- Add WhatsApp alerts.
- Add a daily pre-market summary.
- Store filtered results in CSV.
- Add an LLM layer to explain market impact in natural language.
