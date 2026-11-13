# OpenRouter → Langfuse destination の設定

**対象**: `https://openrouter.ai/workspaces/default/observability/destinations/new/langfuse`
**最終確認**: 2026-11-13（OpenRouter OpenAPI `/observability/destinations` と SDK ドキュメントを実取得）
**台帳**: 本リポジトリ `data/integrations.jsonl` の `openrouter-langfuse`

OpenRouter の観測データ（request / attempt / tokens / cost / latency / outcome）を Langfuse へネイティブ転送する。
転送ではなく自前保持で分析したい場合は [observability-plan.md](./observability-plan.md) を参照（本設定とは排他ではない。複数 destination を同時に有効化できる）。

---

## 0. 前提（2 組の資格情報）

| # | 必要なもの | 入手場所 | 注意 |
|---|---|---|---|
| 1 | Langfuse `baseUrl` / `publicKey` / `secretKey` | Langfuse プロジェクト → Settings → API Keys | `pk-lf-...` / `sk-lf-...`。片方だけあっても不可 |
| 2 | OpenRouter **Management API key** | https://openrouter.ai/settings/management-keys | UI だけで設定するなら不要。推論用の `sk-or-v1-...` では `401 Invalid management key` |

- `baseUrl` の既定例: US `https://us.cloud.langfuse.com` / EU `https://cloud.langfuse.com` / セルフホスト `https://<host>`
- 秘密は台帳に書かない（`setup_fields` は `secret_reference_only` で記録している）

## 1. UI で設定する場合

1. 上の URL を開く（`default` workspace）
2. **Langfuse** を選択
3. 入力する:
   - `Base URL` — Langfuse リージョンの URL
   - `Public Key` — `pk-lf-...`
   - `Secret Key` — `sk-lf-...`
   - `Name` — 例 `bonsai workspace`
4. 生成メタデータの同梱オプション（既定 all off）:

| オプション | 意味 |
|---|---|
| `broadcast_generation_cost` | cost / billing 情報を generation に付ける |
| `broadcast_generation_cost_allocation` | β: トークン種別ごとの内訳（billed cost と整合する時のみ） |
| `broadcast_generation_identity` | 呼び出し元 identity（key / user 由来）を付ける |
| `broadcast_generation_request_context` | リクエスト文脈（session_id 等）を付ける |

5. 必要なら `privacy_mode`（本文を送らずメタデータのみ）/ `sampling_rate`（0.0001〜1）/ `regions`（既定 `global`）
6. Create

## 2. API で設定する場合（再現可能・台帳と一致させやすい）

資格情報は `%USERPROFILE%\.openrouter-langfuse.env`（repo 外・git 管理外）に置く。スクリプトが `-EnvFile` で読む。

```powershell
cd projects\Observability\tools
$envFile = "$env:USERPROFILE\.openrouter-langfuse.env"

# 1) Langfuse 側の鍵が生きているか先に確認（GET /api/public/projects）
.\openrouter-langfuse.ps1 -Action Verify  -EnvFile $envFile

# 2) 管理キーの疎通 + 既存 destination の一覧
.\openrouter-langfuse.ps1 -Action List    -EnvFile $envFile

# 3) 送信内容の確認（鍵は伏字）
.\openrouter-langfuse.ps1 -Action Create -EnvFile $envFile -DryRun -Name "bonsai workspace"

# 4) 作成
.\openrouter-langfuse.ps1 -Action Create -EnvFile $envFile -Name "bonsai workspace" -EnableCostBroadcast
```

env ファイルの中身（テンプレートは作成済み）:

```
OPENROUTER_MANAGEMENT_KEY=
LANGFUSE_PUBLIC_KEY=
LANGFUSE_SECRET_KEY=
LANGFUSE_BASE_URL=https://us.cloud.langfuse.com
```

REST を直接叩く場合:

```
POST https://openrouter.ai/api/v1/observability/destinations
Authorization: Bearer <management key>
Content-Type: application/json

{
  "type": "langfuse",
  "name": "bonsai workspace",
  "config": {
    "baseUrl": "https://us.cloud.langfuse.com",
    "publicKey": "pk-lf-...",
    "secretKey": "sk-lf-..."
  },
  "enabled": true,
  "privacy_mode": false,
  "sampling_rate": 1,
  "regions": ["global"],
  "broadcast_generation_cost": true
}
```

- 1 type あたり最大 **5** destination
- `api_key_hashes` で転送対象の OpenRouter API キーを絞れる（省略 = 全キー。他 workspace の hash を混ぜると 400）
- `workspace_id` 省略時は default workspace（workspace スコープの management key は自 workspace のみ）
- `type` は stable な enum のみ受理: `arize / braintrust / clickhouse / datadog / grafana / langfuse / langsmith / newrelic / opik / otel-collector / posthog / ramp / s3 / sentry / snowflake / weave / webhook`

## 3. 動作確認

1. OpenRouter observability → Destinations に 1 行増え、`enabled=true`
2. OpenRouter 経由で数リクエスト流す（`projects/model-optimization` の bench でも可）
3. Langfuse → Tracing に generation が現れる。`usage.cost` は `broadcast_generation_cost` が true のときのみ
4. 失敗時: OpenRouter 側 destination の status、Langfuse 側の Ingestion API 到達性（`/api/public/ingestion`）、`baseUrl` のリージョン違いを順に確認

## 4. 現状のブロッカー（2026-11-13 実測）

| 項目 | 状態 |
|---|---|
| `OPENROUTER_API_KEY`（`sk-or-v1-0d647...`、env と opencode auth.json の両方） | `/api/v1/key` が **401 `User not found.`** → 鍵は無効（`/api/v1/models` は未認証で通る）。wiki #384 の恒久反映は未解決のまま |
| Management API key | 未保有。`/observability/destinations` は `401 Invalid management key` |
| Langfuse プロジェクト（`pk-lf-` / `sk-lf-` / baseUrl） | ローカル・Drive 台帳・topology.yaml のいずれにも存在せず、ローカル Langfuse / docker も無し |

→ 上記 2 組が揃えば `tools/openrouter-langfuse.ps1` の 4 コマンドで完了する。
