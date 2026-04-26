# LLM Runtime Configuration

LLM inference runs inside the platform API process — there is no separate runtime to start. This page covers the environment variables that bound runtime behaviour, where local model files must live for `llama_cpp`, and the most common failure modes.

For the design context, see [LLM Platform Layer](../concepts/llm-platform.md).

## Start

LLM inference is served by the same process as the rest of the REST API. Start it the usual way from `aurelion-kernel/`:

```bash
uv run uvicorn src.runtimes.platform_api.main:app \
  --host 0.0.0.0 \
  --port 8000
```

No additional flags or env vars are required to enable the LLM endpoints — they come up with the rest of the API. If `llama_cpp` is the configured provider for any registered model, the optional dependency must be installed:

```bash
uv pip install "aurelion-kernel[llm-llama-cpp]"
```

If the dependency is missing, registration of `llama_cpp` models still succeeds, but the first inference call against such a model fails with `LLMProviderUnavailableError`.

## Configuration

All four LLM knobs are read from `LLMSettings` (pydantic-settings v2) at process start. They are independent of the kernel-wide `Settings` block.

| Variable | Default | Description |
|---|---|---|
| `LLM_MAX_LOADED_MODELS` | `2` | Max number of provider instances kept warm in the in-process LRU cache. When exceeded, the least-recently-used provider is evicted and its `abort()` is called. |
| `LLM_MAX_MESSAGES` | `32` | Max number of messages allowed in a single inference request. Exceeding this returns `422`. |
| `LLM_MAX_CHARS_PER_MESSAGE` | `32000` | Max characters in any one message's `content`. Exceeding this returns `422`. |
| `LLM_MAX_TOTAL_CHARS` | `128000` | Max total characters across all messages in a single request. Exceeding this returns `422`. |

All four must be `>= 1`. Setting any of them to `0` or a negative integer causes `LLMSettings` to fail validation at process start.

Sizing notes:

- Each loaded GGUF model occupies roughly its on-disk size in RAM (more with `n_gpu_layers > 0` if the GPU offloads are active). Set `LLM_MAX_LOADED_MODELS` based on the host's resident memory budget, not on model count alone.
- The character limits are pre-tokenisation guards. They are deliberately loose compared to typical context windows so that legitimate prompts pass without the platform second-guessing tokenisation behaviour.

## GGUF file placement

For `provider = llama_cpp`, the `LLMModel.local_path` field must be an absolute filesystem path that the platform API process can read. The service validates the path at registration time (`POST /api/v0/llm/models`) and on every update.

Requirements:

- **Absolute path.** Relative paths are rejected at registration with a `422`.
- **Regular file.** Symlinks to regular files are accepted; directories and special files are not.
- **Readable by the API process.** `os.access(path, os.R_OK)` must be true for the user the API runs as.
- **Stable.** Moving or renaming the file under a registered model invalidates the next inference call. Update the model row first (`PATCH /api/v0/llm/models/{id}`), then move the file — or vice versa, but expect transient errors during the gap.

A common production layout:

```
/opt/aurelion/llm-models/
├── llama-3.1-8b-instruct.Q4_K_M.gguf
├── qwen2.5-7b-instruct.Q5_K_M.gguf
└── nomic-embed-text-v1.5.Q4_K_M.gguf
```

In Docker deployments, mount the directory read-only into the API container at the same path you registered, e.g. `-v /opt/aurelion/llm-models:/opt/aurelion/llm-models:ro`. Registering a `local_path` that is valid on the host but not inside the container will pass validation only if the validation runs in the container — register from inside, or use the same path on both sides.

## Cache invalidation

The `LLMFactory` cache is invalidated synchronously when a model row mutates in a way that changes provider behaviour: `is_active=false`, `local_path`, `endpoint_url`, `model_ref`, or `DELETE`. The next inference call against that model rebuilds the provider with fresh config. Profile changes do not invalidate the cache — profiles are read at inference time, and the cache is keyed by `model_id`.

Operationally this means: if you swap a GGUF file under a registered model without changing any model field, callers will keep using the old provider until the row is touched or the cache evicts it under LRU pressure. Either `PATCH` the model (e.g. set `is_active=true` to itself) or restart the process to force a clean reload.

## Logging

Every inference call emits one structured log record to `aurelion.logs` with `component=llm_inference`. The record carries `status` (`success` | `error` | `aborted`), `model`, `model_id`, `execution_profile`, `execution_profile_id`, `tokens_used`, `latency_ms`, optional `ttft_ms`, and `correlation_id` from the request. See the [LLM Model reference](../reference/llm-model.md#logging) for the full field list.

This log is the primary observability surface for the LLM layer. There is no separate metrics endpoint and no in-memory counter — wire the SIEM or log buffer consumer to filter on `component=llm_inference` for dashboards.

## Troubleshooting

**`422` on `POST /api/v0/llm/models` with `local_path is not readable` or `model file not found`.**
The path is missing, points at a directory, or the API process user cannot read it. Check `ls -l <path>` from the API user's shell; in Docker, exec into the container and re-check inside.

**`422` on `POST /api/v0/llm/models` with `local_path is required` for a `llama_cpp` model.**
The provider was set to `llama_cpp` without a `local_path`. The validation lives in the service layer, not the schema — the field is optional on the type but mandatory on this provider.

**`500` on `POST /api/v0/inference` with `LLMProviderUnavailableError`.**
The `llama_cpp` model is registered but `llama-cpp-python` is not installed in the API process. Install the optional extra (`uv pip install "aurelion-kernel[llm-llama-cpp]"`) and restart the runtime.

**`500` on `POST /api/v0/inference` with `LlamaCppLoadError`.**
The GGUF file became unreadable since registration (moved, permissions changed, mount unmounted). Verify the file, then `PATCH` the model or restart the process to force a reload.

**`422` on inference with "Too many messages" / "Message content too long" / "Total message chars too long".**
The request exceeds one of the `LLM_MAX_*` limits. Either trim the prompt or raise the limit (and remember the memory implications). The exact limit hit is in the response body.

**Stream stalls with no tokens.**
SSE clients sometimes buffer until newlines arrive. Verify the client is reading line-by-line and not waiting for `Content-Length`. The server sends one `data:` line per token followed by a blank line.

**Mid-stream `data: {"error": ..., "done": true}` then close.**
The provider raised during generation. The error class name is in the `error` field; the full traceback is in the corresponding log record on `aurelion.logs` (matching `correlation_id`). The HTTP status stays `200` because the SSE response had already begun — error mapping for streams is by event, not by status code.
