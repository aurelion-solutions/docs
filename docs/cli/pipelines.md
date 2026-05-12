# CLI — Pipelines

Reference for `al pipelines …` — read-only inspection of pipeline definitions
and pipeline runs against the platform orchestrator.

All commands accept:

- `--format text|json` — output format. `text` (default) prints a compact
  human-readable summary; `json` prints the response body verbatim with
  `indent=2`.
- `--base-url` — platform API base URL. Falls back to `AURELION_API_URL`.

Errors go to stderr. Exit code `1` on API or connection error; exit code `2`
on client-side parameter validation (e.g. an invalid UUID, or `--args` that
is not a JSON object), surfaced either by Typer or by the command itself.

See also: [Pipeline Runs API](../reference/pipeline-runs-api.md),
[Pipeline YAML](../reference/pipeline-yaml.md),
[Pipeline Orchestrator concepts](../concepts/pipeline-orchestrator.md).

---

## `al pipelines list`

List all pipeline definitions currently loaded by the kernel.

| Option | Description |
|---|---|
| `--format` | `text` (default) \| `json` |
| `--base-url` | Platform API base URL |

Calls `GET /api/v0/pipelines`. Response is a `list[PipelineSummary]`.

Text output — one line per pipeline:

```
<name>                          v<version>  steps=<n>  triggers=<n>
```

```bash
al pipelines list
al pipelines list --format json
```

---

## `al pipelines show NAME`

Show full details for a single pipeline definition: header, triggers, and
ordered steps.

| Option | Description |
|---|---|
| `NAME` (positional) | Pipeline name as declared in the YAML definition |
| `--format` | `text` (default) \| `json` |
| `--base-url` | Platform API base URL |

Calls `GET /api/v0/pipelines/{name}`. Response is a `PipelineDetail`
(summary fields plus `args_schema`, `steps[]`, `content_hash`, `source_path`).

`404` → `Pipeline '<name>' not loaded` printed to stderr; exit code `1`.

```bash
al pipelines show application_sync
al pipelines show application_sync --format json
```

---

## `al pipelines runs list`

List pipeline runs, newest first, with optional filters.

| Option | Description |
|---|---|
| `--pipeline` | Filter by pipeline name (`pipeline_name` query param) |
| `--status` | Filter by run status. Repeatable: `--status completed --status failed` |
| `--limit` | Max results (default `50`, kernel caps at `200`) |
| `--offset` | Pagination offset (default `0`) |
| `--format` | `text` (default) \| `json` |
| `--base-url` | Platform API base URL |

Calls `GET /api/v0/pipeline-runs`. `--status` values are passed through as
repeated `status=` query params; the kernel accepts any `PipelineRunStatus`
enum value (`pending`, `running`, `awaiting_event`, `cancelling`,
`completed`, `failed`, `failed_timeout`, `cancelled`).

The CLI does not pre-validate `--limit` against the `200` cap; a request
above the cap returns `422` from the kernel and is surfaced verbatim.

Text output — one line per run:

```
<id>  <pipeline_name>  v<version>  <status>  started=<ts>  finished=<ts>
```

```bash
al pipelines runs list
al pipelines runs list --pipeline application_sync
al pipelines runs list --status completed --status failed --limit 25
```

---

## `al pipelines runs get RUN_ID`

Show full details for a single pipeline run, including the ordered step-run
attempts.

| Option | Description |
|---|---|
| `RUN_ID` (positional) | Pipeline run UUID (validated by Typer; non-UUID → exit `2`) |
| `--format` | `text` (default) \| `json` |
| `--base-url` | Platform API base URL |

Calls `GET /api/v0/pipeline-runs/{run_id}`. Response is a `PipelineRunDetail`
(summary fields + `args` + `steps[]`).

Text output prints a header block (`id`, `pipeline`, `version`, `status`,
`trigger_source`, `current_step`, `started_at`, `finished_at`, optional
`error`), followed by one line per step-run attempt:

```
<step_name>  attempt=<n>  <status>  started=<ts>  finished=<ts>
```

`404` → `Pipeline run not found` printed to stderr; exit code `1`.

```bash
al pipelines runs get 7f1c0b6a-9b7a-4e0d-a1d5-2b8a4f3c1f10
al pipelines runs get 7f1c0b6a-9b7a-4e0d-a1d5-2b8a4f3c1f10 --format json
```

---

## `al pipelines run NAME`

Trigger a new pipeline run.

| Option | Description |
|---|---|
| `NAME` (positional) | Pipeline name as declared in the YAML definition |
| `--args` | Pipeline args as a JSON object. Default: `{}` |
| `--version` | Pipeline version (int). Omitted from the request body when not supplied — the kernel resolves the active version |
| `--format` | `text` (default) \| `json` |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/pipeline-runs` with body
`{"pipeline_name": NAME, "args": <parsed>, "pipeline_version": <version>?}`.

`--args` is validated client-side before the request is sent:

- invalid JSON → `Invalid --args JSON: <error>` on stderr, exit `2`
- JSON that is not an object (e.g. a list, number, string, null) →
  `Invalid --args JSON: must be a JSON object (dict)` on stderr, exit `2`

Both `200` (idempotent dedupe — kernel returned an existing run for the same
`(pipeline, version, args)` tuple) and `201` (a fresh row was inserted) are
treated as success. The `created` field in the response distinguishes the
two cases.

Error mapping:

| Status | Behavior |
|---|---|
| `404` | `Pipeline '<name>' not loaded` on stderr; exit `1` |
| `422` with a `detail` field | `Invalid args: <detail>` on stderr; exit `1` |
| `422` without `detail`, or any other non-2xx | Generic `API error <code>: <body>`; exit `1` |

Text output:

```
pipeline_run_id=<uuid>
status=<pending|running|...>
version=<n>
created=<true|false>
```

```bash
al pipelines run application_sync
al pipelines run application_sync --args '{"application_id": "..."}'
al pipelines run application_sync --version 1 --args '{}' --format json
```

---

## `al pipelines runs cancel RUN_ID`

Cancel an in-flight pipeline run.

| Option | Description |
|---|---|
| `RUN_ID` (positional) | Pipeline run UUID (validated by Typer; non-UUID → exit `2`) |
| `--format` | `text` (default) \| `json` |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/pipeline-runs/{run_id}/cancel` with an empty JSON body.

Error mapping:

| Status | Behavior |
|---|---|
| `404` | `Pipeline run not found` on stderr; exit `1` |
| `409` | Kernel `detail` printed verbatim (e.g. run is already in a terminal state); exit `1` |
| Other non-2xx | Generic `API error <code>: <body>`; exit `1` |

Text output:

```
run_id=<uuid>
status=<cancelling|cancelled>
```

```bash
al pipelines runs cancel 7f1c0b6a-9b7a-4e0d-a1d5-2b8a4f3c1f10
```

---

## `al pipelines runs retry RUN_ID`

Create a new pipeline run that retries a previous one. The original run is
not mutated — `retry` produces a fresh run linked via `retry_of_run_id`.

| Option | Description |
|---|---|
| `RUN_ID` (positional) | UUID of the run to retry (validated by Typer; non-UUID → exit `2`) |
| `--format` | `text` (default) \| `json` |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/pipeline-runs/{run_id}/retry` with an empty JSON body.

Error mapping:

| Status | Behavior |
|---|---|
| `404` | `Pipeline run not found` on stderr; exit `1` |
| `409` | Kernel `detail` printed verbatim (e.g. source run is not in a retryable state); exit `1` |
| Other non-2xx | Generic `API error <code>: <body>`; exit `1` |

Text output:

```
run_id=<new uuid>
retry_of_run_id=<original uuid>
status=<pending|running|...>
pipeline=<name>
version=<n>
```

```bash
al pipelines runs retry 7f1c0b6a-9b7a-4e0d-a1d5-2b8a4f3c1f10
al pipelines runs retry 7f1c0b6a-9b7a-4e0d-a1d5-2b8a4f3c1f10 --format json
```
