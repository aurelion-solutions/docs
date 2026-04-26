# LLM Model

A registered Large Language Model that the platform can call. An `LLMModel` row holds connection metadata (provider, endpoint, local path, model reference) and inference defaults (`context_window`, `max_total_tokens`, `default_params`). Credentials are not stored on the model — when a remote provider needs an API key, the model points at a [Secret](secrets.md) via `secret_id`.

The `provider` field uses the shared `llm_provider` Postgres enum, which is owned by this slice. Other slices that reference the enum reuse it without recreating the type.

## Fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | string | Unique human-readable identifier (1–255 chars) |
| `description` | string \| null | Free-form description |
| `provider` | enum | One of `llama_cpp`, `openai`, `ollama` |
| `local_path` | string \| null | Absolute filesystem path for `llama_cpp` GGUF files |
| `endpoint_url` | string \| null | Base URL for remote providers (`openai`, `ollama`) |
| `model_ref` | string \| null | Provider-side model identifier (e.g. `gpt-4o-mini`, `llama3:8b`) |
| `context_window` | int \| null | Maximum context length in tokens (positive) |
| `max_total_tokens` | int \| null | Soft cap on prompt + completion tokens (positive) |
| `default_params` | JSON | Provider-specific defaults (temperature, top_p, …); defaults to `{}` |
| `secret_id` | UUID \| null | Reference to a [Secret](secrets.md) holding the API key; `ON DELETE RESTRICT` |
| `is_active` | bool | Whether the model is selectable; defaults to `true` |
| `created_at` | datetime | Set on insert |
| `updated_at` | datetime | Updated on every write |

`name` is unique. `provider` and `is_active` are indexed.

Cross-field validity (e.g. `llama_cpp` requires `local_path`, remote providers require `endpoint_url`) is enforced in the service layer, not at the schema or DB level.

## Provider values

| Value | Meaning |
|---|---|
| `llama_cpp` | Local inference via llama.cpp; requires `local_path` |
| `openai` | OpenAI-compatible HTTP API; requires `endpoint_url` and usually `secret_id` |
| `ollama` | Ollama HTTP API; requires `endpoint_url` |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/llm/models` | List all registered LLM models |
| `POST` | `/api/v0/llm/models` | Register a new model |
| `GET` | `/api/v0/llm/models/{model_id}` | Fetch a single model by id |
| `PATCH` | `/api/v0/llm/models/{model_id}` | Update mutable fields on a model |
| `DELETE` | `/api/v0/llm/models/{model_id}` | Remove a model |

Notes:

- `POST` and `PATCH` enforce provider-specific wiring in the service layer: `llama_cpp` requires a readable `local_path`; `openai` and `ollama` require `endpoint_url` (and `secret_id` where the upstream provider needs auth). Configuration violations return `422`.
- `PATCH` body is keyed off `model_fields_set` — a field explicitly set to `null` clears the column on the row. The `provider` field is intentionally not patchable; change provider by deleting and re-creating the model.
- `max_total_tokens` may not exceed `context_window`; the service rejects such updates with `422`.
- Mutations that change the in-process provider state (`is_active=false`, `local_path`, `endpoint_url`, `model_ref`) trigger a synchronous `LLMFactory` cache invalidation so the next inference call rebuilds the provider with fresh config. `DELETE` does the same before removing the row.
- Error mapping: not found → `404`; duplicate `name` → `409`; invalid configuration (provider wiring, token limits, unreadable `local_path`) → `422`.

## CLI

CLI bindings land in a later step of Phase 14. This page will be updated when commands ship.

## Inference API

Inference endpoints live next to the LLM slice but operate on an [LLM Execution Profile](llm-execution-profile.md) — they take `execution_profile_id` (not `model_id`) so callers parameterise behaviour by named profile rather than raw model. The selected profile resolves the model, and parameters are merged as `LLMModel.default_params` ⊕ `LLMExecutionProfile.param_overrides`.

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/inference` | Run inference and return the full output as JSON |
| `POST` | `/api/v0/inference/stream` | Run inference and stream tokens as Server-Sent Events |

### Request body

Both endpoints share the same body:

```json
{
  "execution_profile_id": "…UUID…",
  "messages": [
    {"role": "system",    "content": "You are a strict JSON mapping assistant."},
    {"role": "user",      "content": "Analyse this CSV sample…"}
  ]
}
```

- `role` is one of `system`, `user`, `assistant`. Other values are rejected at the schema layer (`422`).
- Size limits are enforced by `LLMSettings` (pydantic-settings v2): `LLM_MAX_MESSAGES` (default `32`), `LLM_MAX_CHARS_PER_MESSAGE` (default `32_000`), `LLM_MAX_TOTAL_CHARS` (default `128_000`). Exceeding any limit returns `422`.
- The service does not interpret prompts. Roles, ordering, and content are the caller's responsibility.

### `POST /api/v0/inference` — JSON response

Returns a single JSON object once generation is complete:

```json
{
  "output": "…",
  "model_id": "…UUID…",
  "execution_profile_id": "…UUID…",
  "tokens_used": 312,
  "latency_ms": 2140.7,
  "ttft_ms": 380.2
}
```

`ttft_ms` (time-to-first-token) may be `null` when the provider returns an empty stream before the final chunk.

### `POST /api/v0/inference/stream` — SSE response

Returns `Content-Type: text/event-stream`. Each SSE `data:` line is a JSON object. Token events are emitted zero or more times, followed by exactly one final event:

```
data: {"token": "Based", "done": false}

data: {"token": " on",   "done": false}

data: {"output": "Based on …", "model_id": "…", "execution_profile_id": "…", "tokens_used": 312, "latency_ms": 2140.7, "ttft_ms": 380.2, "done": true}
```

If the provider raises mid-stream, a single error event is emitted and the stream closes:

```
data: {"error": "LlamaCppGenerationError", "done": true}
```

When the client closes the connection mid-stream, the server detects the disconnect, calls `provider.abort()`, and writes an `aborted` log entry. No further SSE events are emitted on abort.

### Logging

Every inference call emits exactly one structured log entry to `aurelion.logs` (component `llm_inference`) regardless of outcome:

| Field | Notes |
|---|---|
| `status` | `success` \| `error` \| `aborted` |
| `model`, `model_id` | Resolved from the profile |
| `execution_profile`, `execution_profile_id` | From the request |
| `tokens_used` | Provider-reported, or running count for `aborted` |
| `latency_ms` | Wall clock from request start to completion / abort |
| `ttft_ms` | Wall clock to first non-empty token; omitted if no token was emitted |
| `error_code` | Exception class name on `error`; omitted on `success` / `aborted` |
| `correlation_id` | Header `X-Correlation-ID` (auto-generated when absent) |
| `causation_id` | Header `X-Causation-ID` (omitted when absent) |

### Error mapping

| Condition | Status |
|---|---|
| `execution_profile_id` not found | `404` |
| Referenced model not found | `404` |
| Referenced model is `is_active=false` | `422` |
| Message count or size exceeds `LLMSettings` limit | `422` |
| Provider runtime failure (JSON endpoint) | `500` |
| Provider runtime failure (stream endpoint) | `200` with SSE error event, then close |
