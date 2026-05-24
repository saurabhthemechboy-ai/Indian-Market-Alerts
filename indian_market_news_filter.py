#!/usr/bin/env python3
"""
Rule-based Indian market news filter.

This is an informational screening tool, not investment advice. It scores
news items by likely relevance to Indian equities and labels affected sectors.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


HIGH_IMPACT_KEYWORDS = {
    "rbi": 3,
    "repo rate": 3,
    "rate cut": 3,
    "rate hike": 3,
    "inflation": 3,
    "cpi": 3,
    "wpi": 2,
    "gdp": 3,
    "fii": 3,
    "dii": 2,
    "foreign institutional": 3,
    "crude": 3,
    "brent": 3,
    "oil price": 3,
    "rupee": 3,
    "usd/inr": 3,
    "dollar index": 2,
    "us fed": 3,
    "federal reserve": 3,
    "bond yield": 2,
    "10-year": 2,
    "geopolitical": 2,
    "west asia": 3,
    "iran": 2,
    "israel": 2,
    "china": 2,
    "tariff": 2,
    "budget": 3,
    "gst": 2,
    "sebi": 2,
    "election": 3,
    "monsoon": 2,
    "earnings": 2,
    "results": 2,
    "profit": 2,
    "above estimates": 2,
    "below estimates": 2,
    "capex": 2,
    "order win": 2,
    "government announces": 2,
}


SECTOR_KEYWORDS = {
    "Bank Nifty / Financials": [
        "bank",
        "nbfc",
        "hdfc bank",
        "icici",
        "sbi",
        "axis bank",
        "kotak",
        "credit growth",
        "npa",
        "repo rate",
    ],
    "IT": [
        "it stocks",
        "software",
        "nasdaq",
        "tcs",
        "infosys",
        "wipro",
        "hcltech",
        "tech mahindra",
        "dollar",
    ],
    "Oil & Gas": [
        "crude",
        "brent",
        "oil",
        "ongc",
        "reliance",
        "bpcl",
        "hpcl",
        "ioc",
        "gas",
    ],
    "Auto": [
        "auto",
        "vehicle",
        "ev",
        "maruti",
        "mahindra",
        "tata motors",
        "bajaj auto",
        "eicher",
        "sales volume",
    ],
    "FMCG / Consumption": [
        "fmcg",
        "rural demand",
        "monsoon",
        "hindustan unilever",
        "itc",
        "nestle",
        "dabur",
        "britannia",
    ],
    "Metals": [
        "metal",
        "steel",
        "aluminium",
        "copper",
        "iron ore",
        "tata steel",
        "jsw steel",
        "hindalco",
        "vedanta",
    ],
    "Realty": [
        "real estate",
        "realty",
        "housing",
        "home loan",
        "dlf",
        "godrej properties",
        "prestige",
        "sobha",
    ],
    "Infrastructure / Capital Goods": [
        "infra",
        "infrastructure",
        "railway",
        "defence",
        "capital goods",
        "larsen",
        "l&t",
        "order win",
        "capex",
    ],
    "Pharma / Healthcare": [
        "pharma",
        "usfda",
        "drug approval",
        "sun pharma",
        "cipla",
        "dr reddy",
        "apollo hospitals",
    ],
}


BULLISH_PATTERNS = [
    "rate cut",
    "inflation eases",
    "crude falls",
    "oil prices drop",
    "rupee strengthens",
    "fii inflow",
    "fii buying",
    "profit rises",
    "beats estimates",
    "above estimates",
    "order win",
    "gst cut",
    "stimulus",
    "record high",
]


BEARISH_PATTERNS = [
    "rate hike",
    "inflation rises",
    "crude surges",
    "oil prices rise",
    "rupee weakens",
    "record low",
    "fii outflow",
    "fii selling",
    "profit falls",
    "misses estimates",
    "below estimates",
    "downgrade",
    "default",
    "fraud",
    "war",
    "sanction",
]


IGNORE_PATTERNS = [
    "launches campaign",
    "brand ambassador",
    "awareness drive",
    "wins award",
    "appoints celebrity",
    "social media buzz",
]


@dataclass
class NewsSignal:
    text: str
    score: int
    impact: str
    direction: str
    sectors: list[str] = field(default_factory=list)
    matched_keywords: list[str] = field(default_factory=list)
    reason: str = ""


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def split_news_items(raw_text: str) -> list[str]:
    items = []
    for line in raw_text.splitlines():
        line = line.strip(" -\t")
        if line:
            items.append(line)
    if items:
        return items

    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9])", raw_text.strip())
    return [part.strip() for part in parts if part.strip()]


def contains_phrase(text: str, phrase: str) -> bool:
    return re.search(rf"\b{re.escape(phrase)}\b", text) is not None


def classify_direction(normalized_text: str) -> str:
    bullish = sum(1 for pattern in BULLISH_PATTERNS if contains_phrase(normalized_text, pattern))
    bearish = sum(1 for pattern in BEARISH_PATTERNS if contains_phrase(normalized_text, pattern))

    if bullish > bearish:
        return "Bullish"
    if bearish > bullish:
        return "Bearish"
    if bullish and bearish:
        return "Mixed"
    return "Neutral"


def classify_impact(score: int) -> str:
    if score >= 6:
        return "High"
    if score >= 3:
        return "Medium"
    return "Low"


def find_sectors(normalized_text: str) -> list[str]:
    sectors = []
    for sector, keywords in SECTOR_KEYWORDS.items():
        if any(contains_phrase(normalized_text, keyword) for keyword in keywords):
            sectors.append(sector)
    return sectors or ["Broad Market"]


def score_item(text: str) -> NewsSignal:
    normalized_text = normalize(text)

    if any(contains_phrase(normalized_text, pattern) for pattern in IGNORE_PATTERNS):
        return NewsSignal(
            text=text,
            score=0,
            impact="Low",
            direction="Neutral",
            sectors=["Ignore"],
            reason="Promotional or low financial-impact wording.",
        )

    score = 0
    matched_keywords = []
    for keyword, points in HIGH_IMPACT_KEYWORDS.items():
        if contains_phrase(normalized_text, keyword):
            score += points
            matched_keywords.append(keyword)

    sectors = find_sectors(normalized_text)
    direction = classify_direction(normalized_text)

    if "Broad Market" not in sectors:
        score += 1

    if direction in {"Bullish", "Bearish", "Mixed"}:
        score += 1

    impact = classify_impact(score)
    reason_parts = []
    if matched_keywords:
        reason_parts.append("Matched macro/market drivers: " + ", ".join(matched_keywords[:5]))
    if sectors != ["Broad Market"]:
        reason_parts.append("Sector relevance: " + ", ".join(sectors[:3]))
    if not reason_parts:
        reason_parts.append("No major market-moving driver detected.")

    return NewsSignal(
        text=text,
        score=score,
        impact=impact,
        direction=direction,
        sectors=sectors,
        matched_keywords=matched_keywords,
        reason=" ".join(reason_parts),
    )


def filter_signals(items: Iterable[str], min_score: int) -> list[NewsSignal]:
    signals = [score_item(item) for item in items]
    return sorted(
        [signal for signal in signals if signal.score >= min_score],
        key=lambda signal: signal.score,
        reverse=True,
    )


def to_json(signals: list[NewsSignal]) -> str:
    return json.dumps([signal.__dict__ for signal in signals], indent=2)


def to_markdown(signals: list[NewsSignal]) -> str:
    if not signals:
        return "No market-moving news crossed the selected threshold."

    lines = [
        "| Impact | Direction | Score | Affected | News | Reason |",
        "|---|---:|---:|---|---|---|",
    ]
    for signal in signals:
        news = signal.text.replace("|", "\\|")
        reason = signal.reason.replace("|", "\\|")
        sectors = ", ".join(signal.sectors).replace("|", "\\|")
        lines.append(
            f"| {signal.impact} | {signal.direction} | {signal.score} | "
            f"{sectors} | {news} | {reason} |"
        )
    return "\n".join(lines)


def read_input(args: argparse.Namespace) -> str:
    if args.file:
        return Path(args.file).read_text(encoding="utf-8")
    if not sys.stdin.isatty():
        return sys.stdin.read()
    return input("Paste one headline/news item: ")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter news that can affect Indian share markets."
    )
    parser.add_argument(
        "-f",
        "--file",
        help="Text file with one headline/news item per line.",
    )
    parser.add_argument(
        "--min-score",
        type=int,
        default=3,
        help="Only show items with this score or higher. Default: 3.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON instead of a Markdown table.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw_text = read_input(args)
    items = split_news_items(raw_text)
    signals = filter_signals(items, args.min_score)
    print(to_json(signals) if args.json else to_markdown(signals))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
