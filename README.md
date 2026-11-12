# Observability

A structured catalog of observability and telemetry services, starting with the destinations available in OpenRouter.

## Langfuse (priority sink)

Primary LLM observability design for OpenRouter traffic:

- [docs/langfuse-design.md](docs/langfuse-design.md) — Broadcast + SDK, privacy, cost, hamachi boundary
- [docs/langfuse-setup-checklist.md](docs/langfuse-setup-checklist.md) — operator steps
- Workspace logs (vendor UI): https://openrouter.ai/workspaces/default/logs

Integration row: `openrouter-langfuse` in `data/integrations.jsonl` (`verification_status: documented` — not live-tested in-repo).

## Data

- `data/openrouter-destinations.jsonl`: one JSON object per line; initial inventory of destinations shown in the OpenRouter Observability UI.
- `data/services.jsonl`: service inventory.
- `data/integrations.jsonl`: platform × service integration records.
- `beta` records whether the destination was marked Beta in the captured UI.
- `verification_status: listed` means the destination was visible in the UI; it does not imply that credentials, endpoints, payload fields, or a live connection have been independently tested.
- `verification_status: documented` means setup fields were filled from public provider/OpenRouter docs; still not a substitute for a live connection test.

## Data policy

- Never commit API keys, Space Keys, tokens, passwords, or other secrets.
- Add connection details only after checking the provider's current documentation or a successful connection test.
- Keep provider availability, OpenRouter integration support, and provider product capabilities as separate facts.
- Preserve source and verification status for each record.

## Planned extensions

- Live-verify Langfuse Broadcast (`live_trace`, `cost_ok`)
- Provider-specific connection schemas for remaining destinations
- Authentication and endpoint metadata (secret references only)
- Supported regions and payload fields
- Privacy, sampling, and filtering capabilities matrix
- Integration tests and compatibility notes
- Optional export path to analysis — the self-hosted plan below is one such path (yukidaruma CSV as one format)

## Plan: self-hosted analysis on Kaggle

- [docs/observability-plan.md](./docs/observability-plan.md) — OpenRouter Observability を参考に、転送ではなく**データを手元に保持したまま Kaggle で分析する**計画（llm_requests / balance_snapshots / model_catalog）。destination カタログ（本 repo の data/）は将来の転送先候補。
