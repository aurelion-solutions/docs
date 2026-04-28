# Reconciliation

Reconciliation runs the lake-backed diff pipeline for one application: it reads the latest artifact snapshot, materialises a target set, and persists per-row delta items. Apply (writing to `access_facts`) is a separate concern — see `mode` below.

For how the engine works, see [Reconciliation concept](../concepts/reconciliation.md).
For a step-by-step walkthrough, see [Run reconciliation guide](../guides/run-reconciliation.md).

## Run modes

| Mode | What it does | Terminal status |
|---|---|---|
| `review` | Run the diff, persist delta items, do not apply | `pending_apply` |
| `dry_run` | Run the diff, persist delta items, mark the run as a dry run (no apply will follow) | `dry_run_completed` |
| `auto_apply` | Run the diff, then transparently apply approved delta items via `SyncApplyService` in the same request. | `applied` or `partially_applied` |

`review` is the default if `mode` is omitted.

When `mode=auto_apply`, the route reuses the same `AsyncSession` for both phases, so the per-application advisory lock taken during the diff is held until apply finishes. Manual apply (`POST /reconciliation/runs/{id}/apply`) does not inherit that lock — concurrency is enforced at the apply-run level instead (see [Apply](#apply-runs)).

## Concurrency

A Postgres advisory lock is held for the duration of a run, keyed by `application_id`. A second `POST /reconciliation/runs` for the same application while the first is still in flight returns **`409 Conflict`** with `detail: "Reconciliation already running for this application"`. The lock is released on both success and failure paths; no manual cleanup is required.

Different applications run in parallel — the lock is per-application.

## Run record key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `application_id` | UUID | Owning application |
| `status` | string | `running`, `pending_apply`, `dry_run_completed`, `applied`, `partially_applied`, `failed` |
| `mode` | string | `review`, `dry_run`, `auto_apply` (echoed from the request) |
| `observed_snapshot_id` | string | Iceberg snapshot id of the artifact table read at run start |
| `current_snapshot_id` | string | Iceberg snapshot id of the access-facts table at run start |
| `observed_batch_id` | UUID | Lake batch the diff observed (nullable until the run reaches the diff phase) |
| `created_count` | int | Delta items with `status=create` |
| `updated_count` | int | Delta items with `status=update` |
| `revoked_count` | int | Delta items with `status=revoke` |
| `unchanged_count` | int | Rows that matched without drift |
| `error` | string | Populated on `failed`; null otherwise |
| `created_at` / `started_at` / `finished_at` | datetime | Lifecycle timestamps |

## Delta item key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `run_id` | UUID | FK to the run |
| `status` | string | `create`, `update`, `revoke`, `unchanged` |
| `subject_id` / `account_id` | UUID | XOR — exactly one is set |
| `resource_id` | UUID | Target resource |
| `action_slug` | string | One of the seeded action slugs |
| `effect` | string | `allow` or `deny` |
| `valid_from` / `valid_until` | datetime | Validity window (nullable) |
| `created_at` | datetime | Used as the keyset pagination cursor |

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/reconciliation/runs` | Trigger a run |
| `GET`  | `/api/v0/reconciliation/runs/{id}` | Get run record |
| `GET`  | `/api/v0/reconciliation/runs/{id}/delta-items` | List delta items (cursor-paginated) |
| `POST` | `/api/v0/reconciliation/runs/{id}/apply` | Apply approved delta items (see [Apply](#apply-runs)) |

### POST /reconciliation/runs

Request body:

```json
{
  "application_id": "550e8400-e29b-41d4-a716-446655440000",
  "mode": "review"
}
```

Response (`200`):

```json
{
  "id": "...",
  "application_id": "...",
  "status": "pending_apply",
  "mode": "review",
  "observed_snapshot_id": "...",
  "current_snapshot_id": "...",
  "observed_batch_id": "...",
  "created_count": 5,
  "updated_count": 2,
  "revoked_count": 1,
  "unchanged_count": 34,
  "error": null,
  "created_at": "...",
  "started_at": "...",
  "finished_at": "..."
}
```

| Code | Condition |
|---|---|
| 200 | Run completed. Status reflects mode: `pending_apply` for `review`, `dry_run_completed` for `dry_run`, `applied` / `partially_applied` for `auto_apply` |
| 404 | Application not found |
| 409 | Another reconciliation run for the same application is already in flight |
| 422 | Missing or invalid `application_id` / unknown `mode` value |

### GET /reconciliation/runs/{id}

Returns the same `ReconciliationRunRead` shape as the POST response.

| Code | Condition |
|---|---|
| 200 | Run found |
| 404 | Run id unknown |

### GET /reconciliation/runs/{id}/delta-items

Cursor-paginated. Keyset on `(created_at, id)` — stable across concurrent inserts (none happen after the run finishes anyway, but the ordering is deterministic).

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `status` | string | — | Filter by delta status (`create`, `update`, `revoke`, `unchanged`) |
| `limit` | int | `100` | `1..1000` |
| `cursor` | string | — | Opaque cursor returned in `next_cursor` from the previous page |

Response:

```json
{
  "items": [ { "id": "...", "status": "create", "...": "..." } ],
  "next_cursor": "eyJ0cyI6Ii4uLiIsImlkIjoiLi4uIn0"
}
```

When `next_cursor` is `null`, iteration is complete. Cursors are opaque base64url — see [API conventions / pagination](../api/overview.md#pagination).

| Code | Condition |
|---|---|
| 200 | Page returned (possibly empty) |
| 404 | Run id unknown |
| 422 | Unknown `status` value, `limit` out of range, malformed cursor |

## Apply runs

Apply takes the `approved` delta items of a reconciliation run and writes them to the `normalized.access_facts` Iceberg table via `SyncApplyService`. It is the only path that emits `inventory.access_fact.{created,updated,revoked,reactivated}` events.

A reconciliation run can be applied either implicitly (via `mode=auto_apply` on `POST /reconciliation/runs`) or explicitly via `POST /reconciliation/runs/{id}/apply`.

### Apply modes

| Mode | What it does |
|---|---|
| `auto_apply` | Apply every `approved` delta item belonging to the run |
| `manual_apply` | Same as `auto_apply` but invoked manually after a review |
| `selected_items` | Apply only the delta items listed in `item_ids`; all listed items must be in `approved` |
| `dry_run` | Run the mandatory crash-recovery preflight only — no Iceberg writes, no events, all results marked `skipped` |

### Apply run key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key of the apply run |
| `reconciliation_run_id` | UUID | The reconciliation run being applied |
| `mode` | string | `auto_apply`, `manual_apply`, `selected_items`, `dry_run` |
| `status` | string | `running`, `completed`, `partially_applied`, `failed` |
| `applied_count` | int | Items written successfully |
| `failed_count` | int | Items that failed to write |
| `started_at` / `finished_at` | datetime | Lifecycle timestamps |
| `error` | string | Populated on `failed`; null otherwise |

### POST /reconciliation/runs/{id}/apply

Request body:

```json
{
  "mode": "manual_apply",
  "item_ids": null
}
```

`item_ids` is required when `mode=selected_items` and must be `null` or omitted otherwise.

Response (`200`):

```json
{
  "apply_run_id": "...",
  "status": "completed",
  "applied_count": 7,
  "failed_count": 0,
  "snapshot_ids": {
    "create": 41,
    "update": 42,
    "revoke": 43
  }
}
```

`snapshot_ids` is the map of operation bucket to the Iceberg snapshot id produced by `lake_writer.write_run_batch`. Empty for `dry_run`.

| Code | Condition |
|---|---|
| 200 | Apply finished (status reflects outcome: `completed`, `partially_applied`, or `failed` with details in `error`) |
| 404 | Reconciliation run not found |
| 409 | An apply run for this reconciliation run is already in `running`, `completed`, or `partially_applied` |
| 422 | Invalid `mode`, missing `item_ids` for `selected_items`, or one of the listed items is not in `approved` |

### Concurrency

Manual apply does not re-acquire the per-application advisory lock taken by reconciliation. Concurrency is enforced at the apply-run level: a second `POST /apply` for the same `reconciliation_run_id` while a previous apply run is still active (or already finished successfully) returns `409`. Crash recovery between row-level writes is handled by the mandatory `preflight_recover_already_written` step, which runs first on every apply call regardless of mode.

## Events

Each run emits domain events on `aurelion.events`:

| `event_type` | When | Key payload fields |
|---|---|---|
| `reconciliation.run.started` | After the run row is persisted, before the diff is computed | `run_id`, `application_id`, `mode`, `correlation_id` |
| `reconciliation.delta.created` | After delta items are persisted, on success | `run_id`, `application_id`, `created_count`, `updated_count`, `revoked_count`, `unchanged_count`, `observed_snapshot_id`, `current_snapshot_id` |
| `reconciliation.run.completed` | After the run reaches its terminal success status | `run_id`, `application_id`, `status` (`pending_apply` or `dry_run_completed`), counts |
| `reconciliation.run.failed` | When the pipeline raises | `run_id`, `application_id`, `error` |

A failed run emits `run.started` followed by `run.failed`. `delta.created` and `run.completed` are not emitted on failure.

When the run is applied (either via `mode=auto_apply` or via `POST /runs/{id}/apply`), `SyncApplyService` additionally emits one of `inventory.access_fact.{created,updated,revoked,reactivated}` per applied delta item. Each payload carries `delta_item_id`, `snapshot_id`, and `reconciliation_run_id` so consumers can stitch the fact back to the originating diff. See [Events and Logs](../concepts/events.md) for envelope shape, correlation handling, and the `inventory.access_fact.*` payload contract.

## CLI

```bash
al reconciliation run --application-id <uuid>
```

CLI flags for `mode` and the new GET endpoints land in a later phase; today the CLI defaults to `review`.

Exit code 0 = run completed. Exit code 1 = application not found, conflict, or other HTTP error.
