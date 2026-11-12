# Langfuse setup checklist (OpenRouter)

Do not paste real keys into git, issues, or screenshots committed to the repo.

## A. Langfuse project

- [ ] Create / select Langfuse project
- [ ] Create API keys (public + secret)
- [ ] Note `baseUrl` for region (EU / US / JP / self-host)
- [ ] Decide privacy_mode default (debug vs shared)

## B. OpenRouter Broadcast

- [ ] OpenRouter → Observability / destination settings
- [ ] Enable Broadcast
- [ ] Add destination type **langfuse**
- [ ] Set `config.baseUrl`, `publicKey`, `secretKey`
- [ ] Enable cost-related broadcast flags if cost tracking needed
- [ ] Run **Test connection**
- [ ] Save destination (`enabled: true`)

## C. Smoke test

- [ ] Send one chat completion via OpenRouter (known model + prompt)
- [ ] Confirm row in [workspace logs](https://openrouter.ai/workspaces/default/logs)
- [ ] Confirm generation in Langfuse UI (model, tokens, latency)
- [ ] If cost enabled: confirm cost present
- [ ] Record date + result in integration notes (`live_trace` / `cost_ok`)

## D. Optional SDK path

- [ ] `pip install langfuse openai`
- [ ] Env: `LANGFUSE_*` + OpenRouter key as `OPENAI_API_KEY`
- [ ] Client `base_url=https://openrouter.ai/api/v1`
- [ ] One scripted call with `usage.include` if needed
- [ ] Nested `@observe` only if agent requires it

## E. Catalog hygiene (this repo)

- [ ] Bump `verification_status` on `openrouter-langfuse` when tested
- [ ] Fill `setup_fields` with **field names only** (no secret values)
- [ ] Keep secrets out of `data/*.jsonl`
