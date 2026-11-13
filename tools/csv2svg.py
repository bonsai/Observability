#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""csv2svg — CSV to SVG horizontal bar chart (POC deliverable, wiki #400).

Reads a CSV, aggregates by a label column, and emits a hand-built SVG
horizontal bar chart. Vanilla SVG only — no libraries, no frameworks
(yukidaruma ADR-002 constraint). Stdlib only.

The first application is the 民謡自治体貢献度通知表 (minyo × municipality
contribution report card).

Usage:
    python csv2svg.py input.csv --out out.svg [--title "..."] \
        [--label-col LABEL] [--value-col VALUE] [--top N] [--suffix "点"]
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

sys.stdout.reconfigure(errors="replace") if hasattr(sys.stdout, "reconfigure") else None


def esc(s: str) -> str:
    return (s or "").replace("&", "&amp;").replace("<", "&lt;") \
                     .replace(">", "&gt;").replace('"', "&quot;")


def to_num(s):
    try:
        return float(str(s or "0").replace(",", "").strip())
    except ValueError:
        return 0.0


def fmt(v: float) -> str:
    return f"{v:,.0f}" if float(v).is_integer() else f"{v:,.1f}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--out", required=True)
    ap.add_argument("--title", default="")
    ap.add_argument("--label-col", default=None, help="label column (default: first)")
    ap.add_argument("--value-col", default=None, help="numeric column (default: second)")
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--width", type=int, default=760)
    ap.add_argument("--row-height", type=int, default=30)
    ap.add_argument("--fill", default="#4A78C2")
    ap.add_argument("--fill-max", default="#2F5FA8")
    ap.add_argument("--suffix", default="", help="value label suffix (e.g. 点)")
    args = ap.parse_args()

    with open(args.input, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        print("no rows in CSV", file=sys.stderr)
        return 1
    cols = list(rows[0].keys())
    label_col = args.label_col or cols[0]
    value_col = args.value_col or (cols[1] if len(cols) > 1 else cols[0])

    agg: dict = {}
    for r in rows:
        label = (r.get(label_col) or "").strip()
        if not label:
            continue
        agg[label] = agg.get(label, 0.0) + to_num(r.get(value_col))
    data = sorted(agg.items(), key=lambda kv: kv[1], reverse=True)[: max(1, args.top)]
    if not data:
        print("no data after aggregation", file=sys.stderr)
        return 1

    row_h = args.row_height
    label_w = 200
    bar_max = args.width - label_w - 100
    top_pad = 56 if args.title else 16
    height = top_pad + row_h * len(data) + 20
    vmax = max(v for _, v in data) or 1.0

    parts = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{args.width}" '
        f'height="{height}" viewBox="0 0 {args.width} {height}" '
        f'font-family="' + "'Hiragino Sans','Yu Gothic','Meiryo',sans-serif" + '">'
    )
    parts.append(f'<rect width="{args.width}" height="{height}" fill="#ffffff"/>')
    if args.title:
        parts.append(f'<text x="{label_w - 8}" y="30" font-size="17" '
                     f'font-weight="bold" fill="#222">{esc(args.title)}</text>')
    vmax_int = vmax.is_integer()
    for i, (label, v) in enumerate(data):
        ry = top_pad + i * row_h
        w = max(1.0, v / vmax * bar_max)
        fill = args.fill_max if v == vmax else args.fill
        vs = f"{v:,.0f}" if vmax_int else f"{v:,.1f}"
        parts.append(f'<text x="{label_w - 8}" y="{ry + 16}" font-size="13" '
                     f'text-anchor="end" fill="#333">{esc(label)}</text>')
        parts.append(f'<rect x="{label_w}" y="{ry + 2}" width="{w:.1f}" '
                     f'height="18" rx="3" fill="{fill}"/>')
        parts.append(f'<text x="{label_w + w + 6:.1f}" y="{ry + 16}" '
                     f'font-size="12" fill="#555">{vs}{esc(args.suffix)}</text>')
    parts.append("</svg>")

    svg = "\n".join(parts) + "\n"
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg, encoding="utf-8")
    print(f"csv2svg: {len(data)} bars -> {out} "
          f"(label={label_col}, value={value_col}, max={vmax:g})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
