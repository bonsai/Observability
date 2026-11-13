# LLM 観測基盤計画 — OpenRouter observability を参考に、Kaggle で自作する

**Home**: bonsai/Observability（ml-repos-analyze から接木、2026-11-12）
**Status**: 計画。ユーザー指示「これらも使っていきたい。DB 分析プロバイダ。真似して Kaggle で自作すべきだが、参考にするまで」→ 本書は**参考研究と計画**のみ（実装は Step 0 から別途）。
**親**: bonsai/wiki #396（ファイル進化計画・姉妹）／ #384（OpenRouter キー）／ #395（kaggle-prediction 照合実験）
**対象データ**: LLM 呼び出し（provider / model / tokens / cost / latency / outcome）の観測。分析は Kaggle。

---

## 0. 確定（2026-11-13 ユーザー）— 分析ターゲット 3 つとティア構造

### 分析ターゲット（観測基盤の適用先）

1. **OpenRouter 使用履歴データ分析** — 本計画の本体（llm_requests / balance / model_catalog）
2. **bonsai repo 分析** — ファイル進化計画（#396）と接続：repo_snapshots / file_manifests / events
3. **民謡自治体貢献度通知表**（新規）— 民謡 × 自治体の貢献度を SVG 通知表として可視化。vanilla JS + SVG 制約（yukidaruma ADR-002）と整合する最初の具体的ユースケース

### ティア構造（ユーザー確定）

| ティア | 計算 | ストレージ | 形式 |
|---|---|---|---|
| **max** | Kaggle | Cloudflare D1 / R2 | JSONL / SQLite / **Parquet（要確認 → 後述）** |
| **colab** | Colab | Google Drive | CSV / JSONL |
| **poc** | py + GH wf | GitHub（data/ + Pages） | CSV / SVG / dataview.js |

- **Parquet は max ティアの分析形式として適切**（列指向・Kaggle/DataFrame native）。正（canonical）は JSONL のまま、Parquet は分析用派生
- SQLite は処理エンジン（進化計画と同じ規約）

### MVP / POC の切れ分け（ユーザー確定）

- **MVP: Langfuse でデータ可視化・インサイト取得** — destination カタログ（data/）に Langfuse の setup_fields 済み（integrations.jsonl 参照：baseUrl / publicKey / secretKey / privacy_mode ほか）。OpenRouter の destination 設定を 1 つ行えば自前 collector 不要で可視化が始まる
- **POC: CSV → GDrive / py + GH wf / SVG + dataview.js on GH** — ファイル進化計画のツール群（tools/）と同型。データは手元保持

### ロードマップ（2026-11-13 ユーザー確定 — 3 つの名前付きデリバラブル）

| フェーズ | デリバラブル | 中身 | 状態 |
|---|---|---|---|
| **POC** | **csv2svg** | CSV → SVG 変換パイプライン（py + GH wf / GH Pages）。最初のアプリ = 民謡自治体貢献度通知表 | **次に作る** |
| **MVP** | **observability**（本 repo） | Langfuse + GAS + AppSheet + Sheets の観測基盤（llm_requests / balance_snapshots / model_catalog） | 計画済み（本書） |
| **MAX** | **yukidaruma** | 計算倉庫本体（Workers + D1 + Google Drive + Muse VM Python worker + Kaggle/Colab） | Phase 0 設計済み（ADR-001/002） |

依存順: **POC（csv2svg）が最初** — ここで確立した SVG 出力の型（vanilla JS + SVG 制約）が MVP/MAX の可視化にも流用される。

### 可視化 / UI レイヤ（2026-11-13 追加 — GAS + AppSheet）

| レイヤ | ツール | 役割 |
|---|---|---|
| 収集・転送 | **GAS**（時間/onChange トリガー） | Drive の evolution JSONL → Sheets 書き出し / Langfuse ingestion POST（UrlFetchApp） |
| 保持 | Google Sheets / Drive | 集計テーブル（AppSheet のソース）＋生 JSONL |
| 閲覧（no-code） | **AppSheet** | Sheets を読むモバイル/web アプリ — 通知表・ダッシュボードの「見る側」。コード不要 |
| 閲覧（LLM 特化） | Langfuse | LLM 観測のトレース・コスト・セッション分析 |
| 閲覧（自作） | vanilla JS + SVG on GH Pages（dataview.js） | 通知表・レポート（yukidaruma ADR-002 制約と整合） |

データフロー: `evolution/*.jsonl`（Drive）→ **GAS** → Sheets → **AppSheet**（モバイル閲覧）／ **Langfuse**（LLM 分析）／ GH Pages **SVG**（通知表）

- AppSheet は free tier で prototype・個人利用可（≤10 ユーザー）
- GAS は 6 分/実行・UrlFetchApp 20k/day — 転送用途には十分。重い分析は max ティア（Kaggle）のまま
- Langfuse ブリッジ経由なら **OpenRouter Management key 不要**（Langfuse 鍵のみで Drive のデータを直接 POST — integrations 調査で判明した 401 問題を回避）

### ngrok / OpenTunnel（topology.yaml 2026-11-12 確定）

- **OpenTunnel = opencode のペアリング/トンネル機能**（`bin/pair-qr.ps1` の opencode pair フロー）。別サービスではない
- OpenCode v2 のリモート入口（port 49375）: **OpenTunnel または ngrok opencode トンネルの二択が台帳に定義済み** → OpenTunnel で ngrok は置換可能
- muse-bridge（port 8765、muse-crx の /ext relay）は**別用途** — yukidaruma の outbound-poll 設計に寄せると不要化する
- LLM 観測基盤にトンネルは無関係（OpenRouter 経由は cloud → cloud）

---

## 0. この repo との関係 — 転送先カタログ vs 自前分析

この repo の `data/*.jsonl`（21 destinations）は、OpenRouter Observability UI で確認できる**観測データの転送先**（SaaS）カタログである:

- services.jsonl: Arize AX / Braintrust / ClickHouse / Comet Opik / Datadog / Elastic / BigQuery / Grafana / Langfuse / LangSmith / New Relic / OTel Collector / PostHog / Sentry / Snowflake / W&B Weave / S3 / Webhook ほか
- integrations.jsonl: 各 destination の setup_fields（api_key / space_key など secret 参照のみ）

**本計画の位置づけ**: SaaS へ転送せず、**データを手元（Drive .metadata）に保持したまま Kaggle で分析する**自前経路。ただしカタログは将来の選択肢として保持する:

- OpenRouter の destination 設定を 1 つ行えば（例: webhook / S3）、自前 collector なしで SaaS 観測が始まる — ただしデータは外部に出る
- events.jsonl / llm_requests.jsonl を **S3-compatible / webhook destination へ転送する**拡張は Step 4 以降の選択肢

## 1. 参考 1 — OpenRouter observability（作りたいものの一覧）

`openrouter.ai/workspaces/<ws>/observability` が見せている機能:

| 機能 | 中身 |
|---|---|
| usage overview | 期間 × provider / model 別の requests・tokens・cost・errors |
| request logs | 1 リクエスト = 1 行（model, provider, status, tokens, cost, 時刻） |
| attempts | 1 リクエストの試行履歴（provider, key, outcome, retry, timing）— フォールバックの記録 |
| model catalog | context 長と価格（input / output per 1M tokens） |
| credits / balance | 残高と消化ペース |
| workspaces | プロジェクト単位の分離 |

## 2. 参考 2 — ngrok AI Gateway のデータモデル（実サンプリング済み）

opencode のツールカタログに AI Gateway 観測ツール群（`aigw_*`）が入った。**データモデルの参考**として実サンプリング:

- `aigw_usage_overview` — 期間集計（cost_usd / requests / errors / error_rate、by provider）。本アカウントは window 内 **0 usage**
- `aigw_list_models` — カタログ（context_length, input/output_usd_per_1m_tokens, surfaces）
- `aigw_get_request` / `aigw_get_request_attempts` — 1 リクエストの試行履歴（provider, key, outcome, retry, timing, tokens, cost）
- `aigw_get_capture` — body のキャプチャ
- **教訓**: 観測の単位は request → attempts（試行ごとに課金）→ provider/model で集計、の 3 段

## 3. 参考 3 — 既存 metrics.db（すでに半分ある）

`C:\Users\dance\.hamachi\metrics.db`（model-optimization skill の正。2026-11-12 実測）:

| テーブル | 行数 | 中身 |
|---|---|---|
| `model_metrics` | **518** | **リクエスト級**: run_id, model, provider, task, prompt, expected, response, smartness, response_time_ms, input_tokens, output_tokens, cost_usd, error, timestamp（3 run: run_20261018 / run_takt_20261111 / run_or_20261111） |
| `model_recommendations` | 72 | run 集計（avg_smartness / total_cost_usd / composite_score / rank） |
| `balance_snapshots` | 29 | OpenRouter 残高の時系列 |
| `usage_log` | **0** | スキーマのみ（model, tokens, cached_tokens, cost, timestamp）— **skill_evolution と同じ「設計先行・未計装」** |
| `forecast_log` | **0** | 残高予測（daily_avg, days_remaining）— 同じく未計装 |

注意: OpenRouter API 直接呼び出し（/api/v1/key, /credits）は **401**（User スコープ鍵 `sk-or-v1-0d6…` が拒否）。#384 の「恒久反映（opencode 再起動）」が未完の可能性 → 要確認。

## 4. 自作スキーマ（正は JSONL、Drive `wiki/.metadata/evolution/observability/`）

ファイル進化計画と同じ規約（1 行 = 1 エンティティ × 1 時点、追記のみ、SQLite は処理エンジン）:

- `llm_requests.jsonl` — 1 行 = 1 リクエスト: `{captured_at, surface, provider, model, key_label, outcome, attempts, input_tokens, output_tokens, cost_usd, latency_ms, source, run_id, error}`
- `balance_snapshots.jsonl` — 1 行 = 1 時点: `{captured_at, total_balance, granted, topped_up, currency}`
- `model_catalog.jsonl` — 1 行 = 1 モデル: `{model, provider, context_length, input_usd_per_1m, output_usd_per_1m, surfaces, captured_at}`

## 5. 収集源（3 系統）

1. **metrics.db エクスポート**（Step 0・新規収集ゼロ）: model_metrics 518 rows + balance_snapshots 29 rows → 上記 JSONL へ
2. **OpenRouter API 定期 pull**（鍵の恒久反映が前提）: credits / activity → provider 観測
3. **独自プロキシ**（将来）: 全 LLM 呼び出しを 1 箇所で記録する gateway（ngrok AI Gateway と同型）。takt / opencode / bench の全経路をこれに寄せる

## 6. Kaggle 分析（OpenRouter のページを模す）

| 分析 | 中身 | 相当 |
|---|---|---|
| usage overview | 期間 × provider / model の requests / tokens / cost / errors | observability トップ |
| per-model table | smartness × cost × latency（model_recommendations 拡張） | model leaderboard |
| error rate | モデル別・時間帯別（400 / 429 / 503） | request logs |
| **free 枠バーンダウン** | 日次 1000 req の消化ペース → 枯渇日予測 | forecast_log の実装 |
| balance 蒸発予測 | balance_snapshots の回帰 | credits ページ |

## 7. 予測（kaggle-prediction フェーズ 1 — 反証可能）

| # | 予測 | 状態 |
|---|---|---|
| Q1 | model_metrics 518 行のエラー率は 20〜40%（free モデルの 400/429 由来） | 未検証 |
| Q2 | 同一モデルの composite_score は run 間で ±0.1 以内に収まる（再現性） | 未検証 |
| Q3 | cost は free 枠中心で有料 usage は $0.50 枠の <10% | 未検証 |
| Q4 | 応答時間の中央値は free モデルで 2〜8 秒 | 未検証 |
| Q5 | usage_log は計装されるまで 0 行のまま | 未検証（負の予測） |

**何を知るべきか**: ①モデル別コスト効率（smartness / cost）②free 枠燃焼ペースと枯渇日 ③エラーの時間帯・モデル依存 ④run 間再現性（ベンチの信頼性）⑤usage_log 計装の効果

## 8. マージ Step

| Step | やること | 完了条件 | 状態 |
|---|---|---|---|
| **0** | `tools/export_observability.py` — model_metrics / balance_snapshots → JSONL | evolution/observability/ に llm_requests.jsonl（≥518 rows） | 未 |
| **1** | Kaggle notebook 01 — usage overview + per-model table | OpenRouter 風の 2 テーブルが再現 | 未 |
| **2** | OpenRouter API pull（鍵解決後）→ provider 観測 | credits が取得できる | 未（401） |
| **3** | usage_log 計装 — takt / opencode の呼び出しフック | usage_log > 0 rows | 未 |

## 9. 完了条件

- evolution/observability/ に llm_requests.jsonl（≥518 rows）と balance_snapshots.jsonl が存在
- Kaggle で usage overview（期間 × model の requests / tokens / cost / errors）が再現できる
- Q1〜Q5 の照合表が埋まる

## 10. 関連

- ml-repos-analyze（health / cluster の ML コア。ファイル進化計画は姉妹: #396）
- #384 OpenRouter キー（401 の恒久反映確認）/ #395 照合実験 / #387 Kaggle Dataset
- skill: model-optimization（metrics.db の正）/ free_quota_check（free 枠バーンダウンと統合）
- 参考: OpenRouter observability / ngrok AI Gateway（aigw_* ツール群）
