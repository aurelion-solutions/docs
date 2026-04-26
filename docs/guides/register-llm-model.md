# How to register an LLM model

This guide walks through registering a local GGUF model in Aurelion, creating an execution profile that points at it, and running a first inference call to verify the wiring.

For the design rationale, see [LLM Platform Layer](../concepts/llm-platform.md). For runtime configuration and troubleshooting, see [LLM runtime configuration](../operations/llm-runtime.md).

## Prerequisites

- Aurelion API running at `http://localhost:8000` (or set `AURELION_API_URL` for the CLI).
- A GGUF model file accessible to the API process at an absolute path. For Docker deployments, the path must be valid inside the container.
- The optional `llm-llama-cpp` extra installed in the API environment:

  ```bash
  uv pip install "aurelion-kernel[llm-llama-cpp]"
  ```

- The `al` CLI installed (used in Step 2; Steps 1 and 3 use `curl`).

## Step 1: Register the model

Send a `POST /api/v0/llm/models` request with the provider type, the absolute path to the GGUF file, and any model-level defaults you want every call to inherit.

```bash
curl -X POST http://localhost:8000/api/v0/llm/models \
  -H "Content-Type: application/json" \
  -d '{
    "name": "llama-3.1-8b-instruct",
    "description": "Local Llama 3.1 8B Instruct, Q4_K_M quant",
    "provider": "llama_cpp",
    "local_path": "/opt/aurelion/llm-models/llama-3.1-8b-instruct.Q4_K_M.gguf",
    "context_window": 8192,
    "max_total_tokens": 4096,
    "default_params": {
      "n_ctx": 8192,
      "n_gpu_layers": 0,
      "temperature": 0.2,
      "top_p": 0.9,
      "max_tokens": 1024
    },
    "is_active": true
  }'
```

On success the response includes the new `id`. Save it — the profile in Step 2 needs it.

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "llama-3.1-8b-instruct",
  "provider": "llama_cpp",
  "is_active": true,
  ...
}
```

Notes:

- `name` must be unique. A duplicate returns `409`.
- `local_path` is validated synchronously: it must be absolute, point at a regular file, and be readable by the API process. A failure here returns `422` with a specific message — see [troubleshooting](../operations/llm-runtime.md#troubleshooting).
- `default_params` is provider-specific. For `llama_cpp`, load-time keys (`n_ctx`, `n_gpu_layers`, `n_threads`, `seed`, `verbose`) are applied when the model is first loaded; generation-time keys (`temperature`, `top_p`, `top_k`, `max_tokens`, `stop`, `repeat_penalty`, `presence_penalty`, `frequency_penalty`) are applied per call.
- `max_total_tokens` may not exceed `context_window`.

For remote providers (`openai`, `ollama`), drop `local_path` and pass `endpoint_url`, `model_ref`, and — for OpenAI-compatible APIs that need auth — a `secret_id` pointing at a registered [Secret](../reference/secrets.md). See the [LLM Model reference](../reference/llm-model.md#provider-values) for the full matrix.

## Step 2: Create an execution profile

Profiles are how callers select inference behaviour. Create at least one profile per use case so that callers reference a stable name rather than the raw model id.

```bash
al llm profile create \
  --name analyst-precise \
  --model-id 550e8400-e29b-41d4-a716-446655440000 \
  --param-overrides '{"temperature": 0.0, "max_tokens": 512}'
```

`param_overrides` can also be loaded from a file:

```bash
al llm profile create \
  --name analyst-creative \
  --model-id 550e8400-e29b-41d4-a716-446655440000 \
  --param-overrides @./profiles/creative.json
```

At inference time, the profile's `param_overrides` are merged on top of the model's `default_params`. Anything not set in the profile falls back to the model's defaults.

Verify the profile is listed:

```bash
al llm profile list
```

Save the printed `id` — the inference call in Step 3 needs it.

## Step 3: Run a first inference call

Use the JSON endpoint to verify the round-trip. The body takes `execution_profile_id` (not `model_id`) and a list of messages.

```bash
curl -X POST http://localhost:8000/api/v0/inference \
  -H "Content-Type: application/json" \
  -H "X-Correlation-ID: $(uuidgen)" \
  -d '{
    "execution_profile_id": "<paste profile id from Step 2>",
    "messages": [
      {"role": "system", "content": "You answer in one short sentence."},
      {"role": "user",   "content": "What is identity governance?"}
    ]
  }'
```

A successful response:

```json
{
  "output": "Identity governance is the practice of managing who has access to what, why, and for how long.",
  "model_id": "550e8400-e29b-41d4-a716-446655440000",
  "execution_profile_id": "...",
  "tokens_used": 23,
  "latency_ms": 1840.3,
  "ttft_ms": 410.1
}
```

The first call against a model is slower than subsequent calls because the GGUF file is loaded into the `LLMFactory` cache. Subsequent calls reuse the cached provider until eviction (LRU when `LLM_MAX_LOADED_MODELS` is exceeded) or invalidation (model row mutated).

## Step 4 (optional): Try the streaming endpoint

For long completions, switch to SSE. The body shape is identical.

```bash
curl -N -X POST http://localhost:8000/api/v0/inference/stream \
  -H "Content-Type: application/json" \
  -d '{
    "execution_profile_id": "<profile id>",
    "messages": [
      {"role": "user", "content": "Write a haiku about access reviews."}
    ]
  }'
```

The response is `text/event-stream`. Each `data:` line is a JSON object with either `{"token": "...", "done": false}` or a final `{"output": "...", "done": true, ...}` summary. See the [Inference API reference](../reference/llm-model.md#post-apiv0inferencestream-sse-response) for the full event contract, including mid-stream error handling and client-disconnect semantics.

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `422 local_path is not readable` on registration | The API process user cannot read the file. Check `ls -l` from the API user's shell or inside the container. |
| `422 max_total_tokens exceeds context_window` | Model defaults conflict. Lower `max_total_tokens` or raise `context_window`. |
| `500 LLMProviderUnavailableError` on first inference | `llama-cpp-python` is not installed in the API environment. Install the `llm-llama-cpp` extra and restart. |
| `404 execution profile not found` | The `execution_profile_id` does not exist. Re-run `al llm profile list`. |
| `422 referenced model is inactive` | The underlying model was set `is_active=false`. PATCH it back to active or repoint the profile by recreating it against a different model. |
| `422 Too many messages` / `Message content too long` | One of the `LLM_MAX_*` limits was hit. See [LLM runtime configuration](../operations/llm-runtime.md#configuration). |

## What's next

- Wire the SIEM or log buffer consumer to filter `component=llm_inference` for dashboards — every call emits exactly one structured log record. See [LLM runtime configuration](../operations/llm-runtime.md#logging).
- Create additional profiles for different use cases (precise vs. creative, short vs. long completions) instead of overriding parameters per call.
- Use the `X-Correlation-ID` request header to join inference calls with the user action that triggered them. The kernel echoes whatever you send and threads it into every log record. See [Events and Logs](../concepts/events.md#correlation-id).
