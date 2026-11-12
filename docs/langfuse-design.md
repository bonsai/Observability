# Langfuse design — OpenRouter Observability

Status: Draft  
Date: 2026-11-13  
Related UI: https://openrouter.ai/workspaces/default/logs  
Catalog ids: `langfuse` (service), `openrouter-langfuse` (integration)

## Purpose

Langfuse is the **primary LLM observability sink** for OpenRouter traffic in this catalog: traces, generations, token usage, cost, latency, and (optionally) input/output for debug.

It answers *what happened on each call* and *why it failed / cost how much*.  
It does **not** replace **hamachi** (balance, model economy, recommendations).

```
Apps / Agents
    │  OpenRouter API
    ▼
OpenRouter ──Broadcast──► Langfuse (preferred path for full coverage)
    │
    └── SDK path (langfuse.openai) ──► Langfuse (nested traces / custom metadata)

Shared usage events ──► hamachi (optional consumer)
```

## Two integration modes

| Mode | How | Best for | Gaps |
|------|-----|----------|------|
| **A. OpenRouter Broadcast** | OpenRouter → Langfuse destination (no app code) | Capture **all** workspace calls; zero instrumentation | Less control over nest/session metadata from app code |
| **B. SDK wrapper** | `langfuse.openai` + `base_url=https://openrouter.ai/api/v1` | Nested spans, `@observe`, custom tags/sessions | Only code paths you instrument |

**Recommendation:** enable **A** as the baseline; add **B** where agents need structured traces (tool loops, multi-step).

## Mode A — Broadcast (no-code)

### Prerequisites

- Langfuse project (cloud or self-host)
- `publicKey` (`pk-lf-…`) and `secretKey` (`sk-lf-…`)
- Base URL by region, e.g.
  - EU: `https://cloud.langfuse.com`
  - US: `https://us.cloud.langfuse.com`
  - JP: `https://jp.cloud.langfuse.com` (if available to the account)
- OpenRouter **management** capability to edit Observability destinations

### Config shape (OpenRouter destination type `langfuse`)

Documented request fields (do not commit real secrets):

```json
{
  "name": "Production Langfuse",
  "type": "langfuse",
  "enabled": true,
  "privacy_mode": false,
  "broadcast_generation_cost": true,
  "broadcast_generation_cost_allocation": true,
  "broadcast_generation_identity": false,
  "broadcast_generation_request_context": true,
  "config": {
    "baseUrl": "https://cloud.langfuse.com",
    "publicKey": "pk-lf-…",
    "secretKey": "sk-lf-…"
  }
}
```

### UI path

1. OpenRouter → Settings → **Observability** (or workspace logs-related settings)
2. Enable Broadcast
3. Add / edit destination **Langfuse**
4. Paste baseUrl + keys
5. Prefer enabling **cost** broadcast flags for hamachi-compatible cost later
6. Test connection → save
7. Generate one chat completion → confirm generation in Langfuse and row in [workspace logs](https://openrouter.ai/workspaces/default/logs)

### Privacy

| Setting | Effect |
|---------|--------|
| `privacy_mode: true` | Strip input/output bodies; keep tokens, cost, timing, model |
| `privacy_mode: false` | Full prompt/completion in Langfuse (debug; higher sensitivity) |

Default for personal debug: `false` only on a non-shared project. Shared/team: start with `true` or sampling.

### Sampling / filters

When the UI exposes them: API key allowlist, sampling rate. For cost accounting accuracy prefer 100% on production keys, or accept statistical cost on sampled traffic.

## Mode B — SDK (code)

```text
pip install langfuse openai
```

Environment (names may be `LANGFUSE_BASE_URL` or `LANGFUSE_HOST` depending on SDK version — set both if unsure):

```text
LANGFUSE_PUBLIC_KEY=pk-lf-…
LANGFUSE_SECRET_KEY=sk-lf-…
LANGFUSE_BASE_URL=https://cloud.langfuse.com
OPENAI_API_KEY=<openrouter_api_key>
```

Pattern:

- Import `from langfuse.openai import openai`
- `OpenAI(base_url="https://openrouter.ai/api/v1", default_headers={…})`
- Optional: `extra_body={"usage": {"include": True}}` so OpenRouter returns cost on the response
- Optional: `@observe()` for parent traces around tool/agent loops

Use when Broadcast alone cannot attach session ids, user ids, or multi-generation tree structure.

## Field mapping (conceptual)

| OpenRouter / call | Langfuse |
|-------------------|----------|
| request id / generation id | trace / generation id (provider-dependent) |
| model | model |
| prompt / completion tokens | usage |
| latency | latency |
| cost (if broadcast or usage.include) | cost / cost_details |
| error | level / status message |
| app session (SDK) | session_id / metadata |

Exact OTEL attribute names evolve; treat Langfuse UI as source of truth after a live test and record results under `verification_status`.

## Relationship to this repo

| Artifact | Role |
|----------|------|
| `data/openrouter-destinations.jsonl` | Langfuse listed as native destination |
| `data/services.jsonl` | Service inventory |
| `data/integrations.jsonl` | `openrouter-langfuse` row — enrich setup fields after live verify |
| `docs/langfuse-setup-checklist.md` | Operator steps |
| `schemas/` | Future: destination config schema without secret values |

## Relationship to hamachi / yukidaruma

| System | Concern |
|--------|---------|
| **Langfuse** | Trace quality, debug, eval hooks |
| **hamachi** | Balance, free tier, cost forecast, model pick |
| **OpenRouter logs UI** | Vendor-native request log |
| **yukidaruma** | Offline/batch analysis of exported CSV/metrics (optional later) |

Export path later: Langfuse or OpenRouter logs → CSV → yukidaruma POC — not required for Langfuse MVP.

## Verification ladder

1. **listed** — in OpenRouter destination list (current catalog state)
2. **configured** — destination saved; test connection OK (no secrets in git)
3. **live_trace** — one generation visible in Langfuse matching a known request
4. **cost_ok** — cost fields populated when cost broadcast / usage.include enabled
5. **sdk_nested** — agent loop shows parent/child observations

Update `data/integrations.jsonl` notes + `verification_status` as each rung is climbed.

## Non-goals

- Committing Langfuse or OpenRouter secrets
- Replacing OpenRouter logs UI
- Guaranteeing free-tier Langfuse retention/limits
- Snowflake-style warehouse (use export + yukidaruma if needed)

## References

- Langfuse × OpenRouter: https://langfuse.com/docs/integrations/other/openrouter
- OpenRouter Langfuse guide: https://openrouter.ai/docs/guides/community/langfuse
- OpenRouter Observability API (destination update): https://openrouter.ai/docs/api/api-reference/observability/update-an-observability-destination
- Workspace logs: https://openrouter.ai/workspaces/default/logs
