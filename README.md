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
- Privacy, sampling, and filtering capabilities matrix
- Optional export path to analysis (e.g. yukidaruma CSV)
