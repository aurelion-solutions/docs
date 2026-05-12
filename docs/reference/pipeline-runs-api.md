# Pipeline Runs API

REST reference for pipeline definitions, pipeline runs, and well-known discovery
endpoints. For the YAML grammar see [Pipeline YAML](pipeline-yaml.md).

Source of truth: `aurelion-kernel/src/platform/orchestrator/routes.py` and
`aurelion-kernel/src/platform/orchestrator/schemas.py`.

## Model

| Entity | Lives where | Purpose |
|---|---|---|
| Pipeline | YAML on disk, cached in memory | Declarative definition: name, version, args schema, triggers, ordered steps |
| `PipelineRun` | `pipeline_runs` table | One execution of a pipeline. Holds status, args, current step, retry chain |
| `StepRun` | `step_runs` table | One attempt of one step within a run. Holds args, result, error, attempt counter |
| `PipelineEventWaiter` | `pipeline_event_waiters` table | One row per in-flight `wait_for_event` step. Has a required `expires_at` |

A `PipelineRun` has many `StepRun` rows (cascade delete). A `StepRun` has at
most one active `PipelineEventWaiter`.

Only `platform/orchestrator/service.py` writes to these tables. Engines invoke
actions through the registry — they do not mutate pipeline state directly.

## PipelineRun fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `pipeline_name` | string | Name from the YAML definition |
| `pipeline_version` | int | Version from the YAML definition; single-version-per-name today |
| `args` | JSONB | Validated against the pipeline's `args_schema` at create time |
| `content_hash` | char(64) | `sha256(canonical_json(args))`. Backs the partial UNIQUE that blocks duplicate in-flight runs with identical `(pipeline_name, pipeline_version, content_hash)` |
| `status` | enum | `pending`, `running`, `awaiting_event`, `cancelling`, `completed`, `failed`, `failed_timeout`, `cancelled`. `aborted` is StepRun-only |
| `trigger_source` | enum | `http` (manual POST), `mq`, `schedule`, `retry`. YAML triggers cannot declare `http` |
| `current_step` | string \| null | Name of the step currently executing (attempt is implicit via `MAX(StepRun.attempt)`) |
| `retry_of_run_id` | UUID \| null | Set on rows created via retry; lets retries bypass the in-flight UNIQUE |
| `worker_id` | string \| null | `<host>-<pid>-<slot>`. Cleared when the run parks on `awaiting_event` |
| `last_heartbeat_at` | datetime \| null | DB-side work-claim heartbeat (3 s refresh, 10 s reclaim window) |
| `started_at` / `finished_at` | datetime \| null | Lifecycle timestamps |
| `error` | string \| null | Populated on `failed` / `failed_timeout`; null otherwise |

`aborted` is **not** a valid `PipelineRun` status — it appears only on `StepRun`
rows as the forensic marker the reclaim transaction stamps on an abandoned
previous attempt.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/pipelines` | List all loaded pipeline definitions |
| `GET` | `/api/v0/pipelines/{name}` | Get full details for one loaded pipeline definition |
| `GET` | `/api/v0/pipeline-runs` | List pipeline runs (filterable; paginated) |
| `POST` | `/api/v0/pipeline-runs` | Manually trigger a pipeline run |
| `GET` | `/api/v0/pipeline-runs/{run_id}` | Get one pipeline run with its step runs |
| `GET` | `/api/v0/pipeline-runs/{run_id}/steps/{step_name}` | Get the latest attempt for one named step |
| `POST` | `/api/v0/pipeline-runs/{run_id}/cancel` | Request cancellation |
| `POST` | `/api/v0/pipeline-runs/{run_id}/retry` | Create a retry run |
| `GET` | `/api/v0/.well-known/pipeline-schema.json` | Merged pipeline YAML JSON Schema with per-action schemas injected |
| `GET` | `/api/v0/.well-known/pipeline-actions.json` | Full registered action catalogue |

### POST /pipeline-runs

Manually trigger a pipeline run. `trigger_source` is always stamped as `http`
by the handler — it is not accepted in the request body.

Request body:

```json
{
  "pipeline_name": "reconcile_app",
  "pipeline_version": 1,
  "args": {}
}
```

`pipeline_version` is optional; when supplied it must match the currently loaded
version. `args` is validated against the pipeline's `args_schema` (Draft 2020-12).

Response (`201` fresh run, `200` idempotent duplicate):

```json
{
  "pipeline_run_id": "00000000-0000-0000-0000-000000000000",
  "status": "pending",
  "pipeline_version": 1,
  "created": true
}
```

Idempotency strategy: a partial UNIQUE index on `(pipeline_name, pipeline_version,
content_hash)` where `status NOT IN ('completed', 'failed', 'failed_timeout',
'cancelled')` blocks a second in-flight run with identical args. The response
includes `"created": false` and returns the existing run when the index fires.

| Code | Condition |
|---|---|
| 201 | Fresh run inserted (`created=true`) |
| 200 | Idempotent hit on the in-flight UNIQUE — existing run returned (`created=false`) |
| 404 | Pipeline name not loaded, or supplied `pipeline_version` does not match the loaded version |
| 409 | Service-level state conflict |
| 422 | `args` failed JSON Schema validation |

### GET /pipeline-runs

Query parameters:

| Parameter | Type | Description |
|---|---|---|
| `status` | enum (repeatable) | Filter by one or more statuses |
| `pipeline_name` | string | Filter by pipeline name |
| `limit` | int (1..200) | Max rows; default 50 |
| `offset` | int (>= 0) | Row offset for pagination; default 0 |

Ordering: `NULLS LAST` on `started_at DESC`, then `id DESC`.

### GET /pipeline-runs/{run\_id} and GET .../steps/{step\_name}

`GET /pipeline-runs/{run_id}` returns the run with its full list of step-run
attempts ordered by `(step_name, attempt)`.

`GET /pipeline-runs/{run_id}/steps/{step_name}` returns the **latest attempt**
for the named step. To inspect prior attempts, fetch the full run and walk its
`steps` array — every attempt has its own `StepRun` row.

### POST /pipeline-runs/{run\_id}/cancel

Request cancellation of an in-flight run.

| Initial status | Outcome |
|---|---|
| `pending` or `awaiting_event` | Transitions to `cancelled` synchronously; returns 200 |
| `running` | Transitions to `cancelling`; returns 200. The runner watcher owns the terminal transition |
| Already `cancelling` or terminal | Returns 409 |

### POST /pipeline-runs/{run\_id}/retry

Create a new run with the same args, `trigger_source=retry`, and
`retry_of_run_id` pointing to the source run.

The source run must be in a terminal status (`completed`, `failed`, `cancelled`,
`failed_timeout`); otherwise 409 is returned. `retry_of_run_id` linkage bypasses
the in-flight UNIQUE index, so retrying a failed run always creates a new row.

| Code | Condition |
|---|---|
| 201 | New retry run created |
| 404 | Source run not found |
| 409 | Source run is non-terminal or cancelling |

## Well-known discovery

The two `/.well-known/` endpoints exist so external tooling (Engineering Studio,
generators, validators) can introspect what the kernel can run without scraping
source code.

| Endpoint | Returns |
|---|---|
| `GET /api/v0/.well-known/pipeline-schema.json` | The pipeline YAML grammar (JSON Schema). Per-action arg and result schemas are merged into `$defs.action_args` and `$defs.action_results`. The merge is additive — existing `$defs` entries are not overwritten |
| `GET /api/v0/.well-known/pipeline-actions.json` | Array of `ActionDescriptor` — one entry per registered `(engine, action)` pair, with `idempotent`, `args_schema`, `result_schema` |

Both endpoints reflect the in-memory state of the action registry and the loader
cache. They do not require authentication and are safe to poll.

A snapshot of the structural grammar (without per-action arg/result merges) is
also bundled inside the Engineering Studio VS Code extension and registered via
`contributes.yamlValidation`, so basic YAML autocomplete and validation work
without a kernel connection. See
[Engineering Studio — Commands and Views](engineering-studio.md#pipeline-yaml-editing).

## Error shape

All error responses use FastAPI's default shape:

```json
{"detail": "<message>"}
```

## CLI

Full CLI reference: [CLI — Pipelines](../cli/pipelines.md).

## Source of truth

- `aurelion-kernel/src/platform/orchestrator/routes.py`
- `aurelion-kernel/src/platform/orchestrator/schemas.py`
