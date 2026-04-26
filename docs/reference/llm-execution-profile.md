# LLM Execution Profile

A named, reusable bundle of inference parameters that points at a single [LLM Model](llm-model.md). An `LLMExecutionProfile` lets callers say "use the `analyst-precise` profile" instead of repeating model id and a dict of sampling parameters at every call site. The profile holds only what overrides the model's defaults — anything not set in `param_overrides` falls back to `LLMModel.default_params`.

The model link is a plain foreign key (`model_id`, `ON DELETE RESTRICT`). There is no SQLAlchemy `relationship()` between profiles and models — cross-entity joins stay explicit, consistent with the rest of the LLM slice.

## Fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | string | Unique human-readable identifier (1–255 chars) |
| `model_id` | UUID | FK to [LLM Model](llm-model.md); `ON DELETE RESTRICT` |
| `param_overrides` | JSON | Per-call parameter overrides merged on top of the model's `default_params`; defaults to `{}` |
| `created_at` | datetime | Set on insert |
| `updated_at` | datetime | Updated on every write |

`name` is unique. `model_id` is indexed to support listing profiles for a given model.

Per-key validation of `param_overrides` (allowed keys, bounded values) is enforced in the service layer, not at the schema or DB level — the rules depend on `LLMModel.default_params` and runtime `LLMSettings`.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/llm/execution-profiles` | List all execution profiles, sorted by `name` ascending |
| `POST` | `/api/v0/llm/execution-profiles` | Create a new profile bound to an `LLMModel` |
| `GET` | `/api/v0/llm/execution-profiles/{profile_id}` | Fetch a single profile by id |
| `PATCH` | `/api/v0/llm/execution-profiles/{profile_id}` | Update mutable fields on a profile |
| `DELETE` | `/api/v0/llm/execution-profiles/{profile_id}` | Remove a profile |

Notes:

- `POST` requires `name` and `model_id`. The referenced `LLMModel` must exist; an unknown `model_id` returns `422`.
- `PATCH` body is keyed off `model_fields_set` — only supplied fields are written. The schema is `extra='forbid'`: `model_id` is intentionally absent and rejected with `422`. Re-pointing a profile at a different model is not supported; create a new profile instead.
- `param_overrides` is replaced wholesale on `PATCH`, not merged. Pass the full desired dict.
- Explicitly setting `name` or `param_overrides` to `null` returns `422` — both columns are `NOT NULL`. Omit the field instead.
- Profile changes do not invalidate the `LLMFactory` cache. Profiles are read at inference time; cached provider instances are keyed by `model_id`.
- Error mapping: not found → `404`; duplicate `name` → `409`; invalid configuration (unknown `model_id`, `null` on `NOT NULL` field) → `422`.

## CLI

| Command | Description |
|---|---|
| `al llm profile list` | List all execution profiles (`id  name  model=<model_id>`) |
| `al llm profile show <id>` | Print a single profile as indented JSON |
| `al llm profile create --name STR --model-id UUID [--param-overrides JSON\|@path]` | Create a new profile; `--param-overrides` accepts inline JSON or `@path/to/file.json` |
| `al llm profile update <id> [--name STR] [--param-overrides JSON\|@path]` | Send only the supplied fields; omitted flags are not sent (no phantom nulls) |
| `al llm profile delete <id> --yes` | Delete a profile; `--yes` is required, otherwise the command exits with code 1 without calling the API |

## Inference

Profiles are how callers select inference behaviour. Both `POST /api/v0/inference` and `POST /api/v0/inference/stream` take `execution_profile_id` (not `model_id`) and merge parameters as `LLMModel.default_params` ⊕ `LLMExecutionProfile.param_overrides`. See the [Inference API](llm-model.md#inference-api) section on the LLM Model page for request/response shape, SSE event format, logging, and error mapping.
