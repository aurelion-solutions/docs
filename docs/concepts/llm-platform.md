# LLM Platform Layer

Aurelion treats large language models as a controlled platform capability, not as a hidden integration inside a product. The LLM layer lives next to logs, secrets, and storage in `src/platform/llm/` — it owns the registry of models, the inference contract, and the operational knobs that bound runtime behaviour.

## Why this is a platform layer

LLMs in an identity governance system make policy-shaped decisions: mapping connector data, classifying access, summarising findings. Two things follow from that:

- **Determinism comes first.** The platform must be able to answer "which model handled this request, with which parameters, in which version" for every inference call. That requires named, versioned configuration — not ad-hoc inline calls from a feature.
- **Inference is shared infrastructure.** Multiple products (IGA, IDP) and engines (normalization, access analysis) will eventually call into LLMs. None of them should own the lifecycle of a model file or an HTTP client to a remote provider.

The LLM layer encodes both: configuration is data in the database, inference goes through one factory, and every call emits exactly one structured log record on `aurelion.logs`.

## The three concepts

```
LLMModel  ──(model_id)──>  LLMExecutionProfile
   │                              │
   │ provider, local_path,        │ param_overrides
   │ default_params, secret_id    │ (per-call sampling)
   ▼                              ▼
AbstractLLMProvider  <─resolved─  POST /api/v0/inference
   (LlamaCppProvider, …)
```

**LLMModel** — a registered model the platform is allowed to call. It carries the provider type (`llama_cpp`, `openai`, `ollama`), wiring (`local_path`, `endpoint_url`, `model_ref`, optional `secret_id`), and the model-level defaults (`context_window`, `max_total_tokens`, `default_params`). Models are admin-managed; you do not register a model from inside a feature.

**LLMExecutionProfile** — a named bundle of inference parameters bound to one model. Profiles are how callers select behaviour: instead of repeating `model_id` and a sampling dict, a feature says "use the `analyst-precise` profile". The profile's `param_overrides` are merged on top of the model's `default_params` at inference time.

**AbstractLLMProvider** — the runtime interface. One provider class per provider type implements `stream(messages, params)` as an async generator and `abort()` as an idempotent cooperative cancel. `LlamaCppProvider` is the in-tree implementation; remote providers slot in next to it.

Profiles point at models by FK only — there is no SQLAlchemy `relationship()` between the two. Joins stay explicit, consistent with the rest of the platform layer.

## Inference flow

A single inference call goes:

1. Caller `POST`s to `/api/v0/inference` (or `/inference/stream`) with `execution_profile_id` and `messages`.
2. The service resolves the profile, then the model. Inactive models, missing profiles, and over-size requests are rejected before any provider is touched.
3. The `LLMFactory` returns a cached provider instance keyed by `model_id`, or constructs and caches a new one. The cache is bounded by `LLM_MAX_LOADED_MODELS` and evicts least-recently-used models, calling `abort()` on the evicted instance.
4. Parameters are merged: `LLMModel.default_params` ⊕ `LLMExecutionProfile.param_overrides`.
5. The provider's `stream()` is consumed. The JSON endpoint accumulates and returns one response. The SSE endpoint forwards token events as they arrive.
6. Exactly one log record is emitted on `aurelion.logs` with `status` ∈ {`success`, `error`, `aborted`}, latency, time-to-first-token, tokens used, and the request's `correlation_id`.

The service layer never interprets the prompt. Roles, ordering, and content are the caller's responsibility — the platform validates only the size limits and the model/profile bindings.

## Determinism and bounded surface

Several decisions are deliberate:

- **Profiles, not raw model ids, on the inference API.** Callers parameterise behaviour by name. Swapping the underlying model (e.g. moving from one GGUF to another) is a profile-side change; calling code does not move.
- **No prompt templates in the platform.** Templates belong to the feature that owns the prompt. The platform is a transport, not a prompt library.
- **Bounded cache.** The factory caches a small number of providers (default 2). A burst of new model ids does not balloon memory — old providers are evicted and aborted.
- **Bounded request size.** `LLM_MAX_MESSAGES`, `LLM_MAX_CHARS_PER_MESSAGE`, and `LLM_MAX_TOTAL_CHARS` cap every request before the provider is engaged. Unbounded prompts are not a runtime failure mode.
- **One log per call.** Every outcome — success, error, mid-stream abort — produces exactly one structured log record with `component=llm_inference`. Operations does not have to reconstruct calls from sampled data.

## Where it sits in the architecture

The LLM layer is Layer 0 (Platform). Capability engines and products call into it; it does not call up. It owns its own ORM tables (`llm_models`, `llm_execution_profiles`) and the shared `llm_provider` PostgreSQL enum.

Credentials never live on the model row. When a remote provider needs an API key, the model points at a [Secret](../reference/secrets.md) by `secret_id` and the provider resolves it at load time.

Correlation ID propagation is handled by the kernel-wide middleware — every inference log carries the same `correlation_id` as the originating HTTP request, so a single user action (CSV mapping, finding triage) joins cleanly across services. See [Events and Logs](events.md#correlation-id) for the propagation rules.

## Where to read more

- [LLM Model](../reference/llm-model.md) — fields, REST API, error mapping, inference request/response shape, SSE format.
- [LLM Execution Profile](../reference/llm-execution-profile.md) — fields, REST API, CLI commands.
- [Register an LLM model](../guides/register-llm-model.md) — end-to-end walkthrough from registration to first inference call.
- [LLM runtime configuration](../operations/llm-runtime.md) — env vars, GGUF placement, troubleshooting.
