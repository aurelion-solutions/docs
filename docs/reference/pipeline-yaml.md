# Pipeline YAML

The pipeline orchestrator runs declarative, multi-step workflows defined in YAML.
Each pipeline definition lives on disk, is loaded into memory at startup, and is
validated against the JSON Schema at `aurelion-kernel/pipelines/schema.json`
(Draft 2020-12). Each execution is persisted as a `PipelineRun`.

For the REST API and data model see [Pipeline Runs API](pipeline-runs-api.md).

## Top-level shape

A pipeline file has a single top-level key `pipeline`. All four fields are required.

```yaml
pipeline:
  name: my_pipeline        # required
  version: 1               # required
  schema_version: 1        # required; must be 1
  steps: [...]             # required; at least one step
```

| Field | Type | Constraints |
|---|---|---|
| `name` | string | Pattern `^[a-z][a-z0-9_]*$` |
| `version` | integer | `>= 1`. Single version per name at runtime |
| `schema_version` | integer | Must be `1` (const) |
| `args` | object | Optional. Declares pipeline-level argument schema (JSON Schema fragment) |
| `triggers` | array | Optional. Zero or more trigger declarations |
| `steps` | array | Required; at least one item |

## Triggers

YAML triggers fire the pipeline automatically. A pipeline may declare zero or
more triggers. `http` is **not** a valid trigger type — manual triggering is
always available via `POST /api/v0/pipeline-runs` and never declared in YAML.

### MQ trigger

Fires when a message arrives on the `aurelion.events` exchange with a matching
routing key (and optional payload predicate).

```yaml
triggers:
  - type: mq
    routing_key: connector.result.received   # required
    match: {}                                # optional JSONB predicate
    args_from_payload:                       # optional; dotted payload paths
      application_id: application_id
      now: now
```

| Field | Required | Description |
|---|---|---|
| `type` | yes | Must be `mq` |
| `routing_key` | yes | RabbitMQ routing key. `minLength: 1` |
| `match` | no | Optional JSONB containment predicate (see [Matcher semantics](#matcher-semantics)) |
| `args_from_payload` | no | Map of `arg_name → dotted.payload.path`; missing paths yield `null` |

Duplicate deliveries are deduplicated via the partial-UNIQUE index on
`(pipeline_name, pipeline_version, content_hash)` — identical args do not
produce a second in-flight run.

### Schedule trigger

Fires on a cron expression or a plain interval. `cron` and `every` are mutually
exclusive; the schema enforces this via `oneOf`.

```yaml
triggers:
  - type: schedule
    cron: "0 3 * * *"   # 5-field cron expression
    # OR
    every: "30m"         # interval: \d+(s|m|h|d)
    args: {}             # optional; static args passed on each fire
```

| Field | Required | Description |
|---|---|---|
| `type` | yes | Must be `schedule` |
| `cron` | cron-only | 5-field cron expression. Mutually exclusive with `every` |
| `every` | interval-only | Interval expression (e.g. `30m`, `1h`, `1d`). Mutually exclusive with `cron` |
| `args` | no | Static args to pass on each fire |

The beat tick runs every 10 s and is guarded by a Postgres advisory lock
(`_BEAT_LOCK_KEY` in `beat.py`) so only one replica fires per tick window.
Dedupe is DB-backed (one schedule run per cron window) and survives restart.

## Steps

Each step is either an `engine_call` or a `wait_for_event`.

### `engine_call`

Calls a registered engine action. `name`, `engine`, and `action` are required.

```yaml
steps:
  - name: reconcile          # required; unique within pipeline
    engine: reconciliation   # required
    action: run              # required
    args:
      application_id: "${args.application_id}"
    requires: []             # optional; list of step names that must complete first
    on_error: fail           # optional; "fail" (default) or "continue"
    retry: {}                # optional; retry policy (schema expanded post-Step 18)
```

| Field | Required | Description |
|---|---|---|
| `name` | yes | Unique within the pipeline. Pattern `^[a-z][a-z0-9_]*$` |
| `engine` | yes | Target engine name |
| `action` | yes | Action name within the engine |
| `args` | no | Step-level args; may use template syntax |
| `requires` | no | Names of steps that must complete before this step runs |
| `on_error` | no | `fail` (default) or `continue` |
| `retry` | no | Retry policy object |

### `wait_for_event`

Parks the run until a matching event arrives on `aurelion.events` or the timeout
expires. `timeout` is **required** — infinite waits are not supported.

```yaml
steps:
  - name: await_approval
    type: wait_for_event       # required; identifies the step type
    event: approval.granted    # required; routing key to wait for
    match:
      request_id: "${args.request_id}"
    timeout: 24h               # required; e.g. 10m, 1h, 7d
    on_timeout: fail           # optional; only "fail" is currently supported
    requires: [submit_request]
```

| Field | Required | Description |
|---|---|---|
| `name` | yes | Unique within the pipeline |
| `type` | yes | Must be `wait_for_event` |
| `event` | yes | Event type (routing key) to wait for |
| `match` | no | Optional containment predicate |
| `timeout` | yes | Max wait duration. Pattern `^\d+(s\|m\|h\|d)$` |
| `on_timeout` | no | `fail` only (currently) |
| `requires` | no | Steps that must complete first |

## Templating

Args values may reference pipeline-level args and prior step results using the
`${...}` syntax. Template expressions are validated by the loader at startup —
they are not encoded in `schema.json`.

| Form | Resolves to |
|---|---|
| `${args.X}` | The value of pipeline arg `X` passed at run creation |
| `${steps.<name>.result.X}` | Field `X` from the result of a completed step named `<name>` |

Missing paths in `${steps...result...}` resolve to `null`. Circular references
are a loader error.

## Matcher semantics

The matcher handles two independent effects: waiter resolution and MQ-triggered
pipeline start. Both use a containment predicate (`match`).

**`args_from_payload`** — when a trigger fires via MQ, the `args_from_payload`
map extracts pipeline args from the event payload using dotted-path lookup.
Missing paths yield `null`.

**`match` containment** — a `match` block is satisfied when its JSONB is
contained in (`<@`) the event payload. In-process matching uses a Python
recursive subset check. DB-side filtering uses Postgres `<@`.

**Nested-list `<@` caveat** — containment for lists of objects is **not** fully
supported in either path. Flat primitive lists are compared as sets (order-
independent). Nested list comparison (e.g. lists of dicts) may produce false
positives or false negatives. This limitation is documented and deferred to a
later phase. Workaround: use top-level scalar predicates only for `match`.

The matcher acquires `pg_advisory_lock(_MATCHER_LOCK_KEY)` (defined in
`matcher.py`) on a dedicated long-lived session at startup, ensuring only one
replica consumes at a time. A second replica enters a warm-standby sleep loop
(1 s) until the lock is released.

## Worked example: application\_sync

End-to-end ingestion pipeline. Triggered by the `connector.result.received` MQ event.

```yaml
pipeline:
  name: application_sync
  version: 1
  schema_version: 1

  args:
    type: object
    required: [application_id, now]
    properties:
      application_id: {type: string, format: uuid}
      now: {type: string, format: date-time}

  triggers:
    - type: mq
      routing_key: connector.result.received
      match: {}
      args_from_payload:
        application_id: application_id
        now: now

  steps:
    - name: reconcile
      engine: reconciliation
      action: run
      args:
        application_id: "${args.application_id}"

    - name: master_data_apply_person
      engine: reconciliation
      action: master_data_apply
      args:
        run_id: "${steps.reconcile.result.run_id}"
        entity_type: person
      requires: [reconcile]

    - name: master_data_apply_org_unit
      engine: reconciliation
      action: master_data_apply
      args:
        run_id: "${steps.reconcile.result.run_id}"
        entity_type: org_unit
      requires: [reconcile]

    - name: master_data_apply_employee
      engine: reconciliation
      action: master_data_apply
      args:
        run_id: "${steps.reconcile.result.run_id}"
        entity_type: employee
      requires: [reconcile]

    - name: sync_apply
      engine: sync_apply
      action: apply
      args:
        reconciliation_run_id: "${steps.reconcile.result.run_id}"
        mode: auto_apply
      requires:
        - master_data_apply_person
        - master_data_apply_org_unit
        - master_data_apply_employee

    - name: project_eas
      engine: effective_access
      action: project_application
      args:
        application_id: "${args.application_id}"
        now: "${args.now}"
      requires: [sync_apply]
```

**Step table**

| Step | Engine | Action | Requires |
|---|---|---|---|
| `reconcile` | `reconciliation` | `run` | — |
| `master_data_apply_person` | `reconciliation` | `master_data_apply` (entity_type=person) | reconcile |
| `master_data_apply_org_unit` | `reconciliation` | `master_data_apply` (entity_type=org_unit) | reconcile |
| `master_data_apply_employee` | `reconciliation` | `master_data_apply` (entity_type=employee) | reconcile |
| `sync_apply` | `sync_apply` | `apply` (mode=auto_apply) | master_data_apply_* |
| `project_eas` | `effective_access` | `project_application` | sync_apply |

**Pipeline args:** `application_id` (UUID), `now` (ISO-8601 datetime for projection timestamp).

**Trigger payload mapping** (`args_from_payload`):

| Pipeline arg | Payload path | Source |
|---|---|---|
| `application_id` | `application_id` | Staged at ingest |
| `now` | `now` | Server-side timestamp stamped by `engines/ingest/service.py` at emit time |

Both fields are present on every `connector.result.received` delivery since
Phase 18 Step 21. See [Connector Results](connector-results.md#payload-fields).
The pipeline can be driven end-to-end by MQ; manual `POST /pipeline-runs`
remains valid for replay.

`effective_access.project_application` is registered with `idempotent=True`, so
the runner is free to retry the `project_eas` step. The fan-out
`master_data_apply_{person,org_unit,employee}` steps are independently idempotent.

## Well-known schema discovery (cross-link)

Per-action arg and result schemas are injected at runtime into the base grammar
and served at `GET /api/v0/.well-known/pipeline-schema.json`. The merge is
additive — existing `$defs` entries are not overwritten.
See [Pipeline Runs API — Well-known discovery](pipeline-runs-api.md#well-known-discovery).

## Source of truth

- `aurelion-kernel/pipelines/schema.json` — canonical JSON Schema (Draft 2020-12)
- `aurelion-kernel/src/platform/orchestrator/loader.py` — YAML loader and template resolver
