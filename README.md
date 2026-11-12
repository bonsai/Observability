# Observability

A structured catalog of observability and telemetry services, starting with the destinations available in OpenRouter.

## Data

- `data/openrouter-destinations.jsonl`: one JSON object per line; initial inventory of 21 destinations shown in the OpenRouter Observability UI.
- `beta` records whether the destination was marked Beta in the captured UI.
- `verification_status: listed` means the destination was visible in the UI; it does not imply that credentials, endpoints, payload fields, or a live connection have been independently tested.

## Data policy

- Never commit API keys, Space Keys, tokens, passwords, or other secrets.
- Add connection details only after checking the provider's current documentation or a successful connection test.
- Keep provider availability, OpenRouter integration support, and provider product capabilities as separate facts.
- Preserve source and verification status for each record.

## Planned extensions

- Provider-specific connection schemas
- Authentication and endpoint metadata (secret references only)
- Supported regions and payload fields
- Privacy, sampling, and filtering capabilities
- Integration tests and compatibility notes
