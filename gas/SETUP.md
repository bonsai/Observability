# GAS ブリッジ セットアップ — Langfuse トレース + Sheets ダッシュボード

`gas/bridge.gs` を Google Apps Script として設置し、**Langfuse 鍵のみ**で
Drive の観測データ（llm_requests.jsonl）を Langfuse トレース + Sheets ダッシュボードに流す手順。

> OpenRouter の Management key は不要（destination 設定を経由しない直接 POST 経路）。

## 前提

- Drive に `evolution/llm_requests.jsonl` がある（`tools/export_observability.py` の出力をコピー済み）
  - 現在 518 rows（run 3 本分）

## 手順

### 1. Langfuse プロジェクトを作成（1 回のみ）

1. https://cloud.langfuse.com でサインアップ（無料 tier で可）
2. Organization / Project を作成（例: `bonsai` / `ml-metadata`）
3. Project Settings → API Keys で **Public Key（pk-lf-…）** と **Secret Key（sk-lf-…）** を発行
   - Secret Key はこの画面でしか表示されないのでコピーしておく

### 2. Apps Script プロジェクトを作成

1. https://script.new で新規プロジェクトを作成（名前: `observability-bridge` など）
2. `gas/bridge.gs` の中身をエディタに貼り付け
3. 保存

### 3. Script Properties を設定

プロジェクト設定 → スクリプト プロパティで以下を追加:

| プロパティ | 値 |
|---|---|
| `LANGFUSE_HOST` | `https://cloud.langfuse.com` |
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-…` |
| `LANGFUSE_SECRET_KEY` | `sk-lf-…` |
| `EVOLUTION_FOLDER_ID` | Drive フォルダ `wiki/.metadata/evolution` の ID（フォルダを開いた URL の `folders/` 以降） |

### 4. 動作確認（手動実行）

1. エディタで関数を選択: `bridgeLangfuseNow` → 実行
   - 初回は承認ダイアログが出る（Drive / 外部リクエスト / Spreadsheet）→ 承認
   - ログに `Langfuse posted: N traces（LAST_TS=…）` が出れば成功
2. Langfuse の Traces 画面でトレースを確認（model 別・session 別）
3. `updateSheetNow` を実行 → Drive に `observability-dashboard` スプレッドシートができ、
   `requests` / `summary` シートが更新される

### 5. トリガーを設置（1 回のみ）

1. エディタで関数を選択: `setupTriggers` → 実行
2. 毎時 `bridgeLangfuseNow` + `updateSheetNow` が走る

## 動作の仕組み

- `LAST_LANGFUSE_TS`（Script Properties）以降の行だけを投稿。成功後に更新するため
  失敗時は再実行で復元できる
- Langfuse は trace id で重複排除するため二重 POST も安全
- `llm_requests.jsonl` の 1 行 = 1 トレース。metadata に run_id / task / smartness /
  error を持たせるので、Langfuse のダッシュボードで model 別の成功率・スコアが見られる

## 制約

- 1 実行 6 分上限 / UrlFetchApp 20,000 calls/day（この用途では余裕）
- 新しい run が増えたら `tools/export_observability.py` を再実行して
  `llm_requests.jsonl` を差し替える（bridge は timestamp で新着分だけ拾う）
