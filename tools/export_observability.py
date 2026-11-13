#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Export metrics.db observability tables to JSONL (Step 0 of the LLM
observability plan, wiki #398).

Reads the model-optimization skill's metrics.db (read-only) and emits:

    llm_requests.jsonl      — 1 行 = 1 リクエスト（model_metrics 518 rows）
    balance_snapshots.jsonl — 1 行 = 1 時点の残高（29 rows）

These feed the GAS bridge (gas/bridge.gs) → Langfuse / Sheets.
Read-only: the DB is never written.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

sys.stdout.reconfigure(errors="replace") if hasattr(sys.stdout, "reconfigure") else None

REQUEST_FIELDS = [
    "id", "run_id", "model", "provider", "task", "prompt", "expected",
    "response", "smartness", "response_time_ms", "input_tokens",
    "output_tokens", "cost_usd", "error", "timestamp",
]
BALANCE_FIELDS = [
    "id", "total_balance", "topped_up_balance", "granted_balance",
    "currency", "is_available", "timestamp",
]


def export_table(con: sqlite3.Connection, table: str, fields: list[str], out: Path) -> int:
    rows = [dict(r) for r in con.execute(
        f"SELECT {', '.join(fields)} FROM {table} ORDER BY timestamp, id")]
    with out.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return len(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("metrics_db")
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    con = sqlite3.connect(f"file:{Path(args.metrics_db)}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    n_req = export_table(con, "model_metrics", REQUEST_FIELDS, out / "llm_requests.jsonl")
    n_bal = export_table(con, "balance_snapshots", BALANCE_FIELDS, out / "balance_snapshots.jsonl")
    con.close()

    print(f"llm_requests: {n_req} rows / balance_snapshots: {n_bal} rows -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
