# Reconciliation

`inventory_reconcile` runs the lake-backed diff pipeline for one Application and one entity type: it reads the latest raw snapshot, materialises a target set, and persists per-row delta items. Apply (writing to `access_facts` or `accounts`) is owned by `inventory_sync` — see `mode` below.

For how the engine works, see [Reconciliation concept](../concepts/reconciliation.md).
For a step-by-step walkthrough, see [Run reconciliation guide](../guides/run-reconciliation.md).

> Phase 19 renamed `reconciliation` to `inventory_reconcile` and the URL prefix to `/api/v0/inventory-reconciles`. The previous `/reconciliation/...` paths are gone.

## Entity types

| `entity_type` | Diff target |
|---|---|
| `access_fact` | `normalized.access_facts` (Iceberg) — five ops: `create`, `update`, `revoke`, `reactivate`, `noop` |
| `account` | `accounts` PG table — same five ops, computed by `AccountHandler.compute_delta` |

A run is keyed on `(application_id, entity_type)`. Both entity types share the same run-state machine, the same delta-item table, and the same apply API; only the handler and apply target differ.

## Run modes

| Mode | What it does | Terminal status |
|---|---|---|
| `review` | Run the diff, persist delta items, do not apply | `pending_apply` |
| `dry_run` | Run the diff, persist delta items, mark the run as a dry run (no apply will follow) | `dry_run_completed` |
| `auto_apply` | Run the diff, then transparently apply approved delta items via `inventory_sync` in the same request | `applied` or `partially_applied` |

`review` is the default if `mode` is omitted.

When `mode=auto_apply`, the route reuses the same `AsyncSession` for both phases, so the per-`(application, entity_type)` advisory lock taken during the diff is held until apply finishes. Manual apply (`POST /inventory-reconciles/runs/{id}/apply`) does not inherit that lock — concurrency is enforced at the apply-run level instead (see [Apply](#apply-runs)).

## Concurrency

A Postgres advisory lock is held for the duration of a run, keyed on `(application_id, entity_type)`. A second `POST /inventory-reconciles/runs` for the same pair while the first is still in flight returns **`409 Conflict`** with `detail: "Reconciliation already running for this application"`. The lock is released on both success and failure paths; no manual cleanup is required.

Different applications run in parallel — the lock is per-application. `account` and `access_fact` runs for the same application also run in parallel.

## Tunable settings

| Key | Default | Range | Effect |
|---|---|---|---|
| `reconciliation_fetch_batch_size` | `5000` | `1..50000` | DuckDB `fetchmany` batch size used by the pipeline when streaming `raw.access_artifacts`, `raw.accounts`, and `normalized.access_facts` rows |

Settings live in the `runtime_settings` table and are reloaded per-run
via `LakeSettings`; changes apply to the next run for any application
without a kernel restart. Update through `PUT /api/v0/runtime-settings/{key}`.

## Handlers

One handler per `artifact_type` for `entity_type=access_fact` runs, plus `AccountHandler` for `entity_type=account` runs.

### Access-fact handlers

| `artifact_type` | What it models |
|---|---|
| `role` | Generic role grant — one result per artifact |
| `sap_role` | SAP role/tcode grant, typically `action_slug=use` |
| `acl_entry` | NT/POSIX ACE — supports `allow` and `deny` effects |
| `db_grant` | SQL privileges (`SELECT`→`read`, `INSERT/UPDATE/DELETE`→`write`, `EXECUTE`→`execute`, `ADMIN OPTION`→`admin`); N results per artifact, deduplicated |
| `privilege` | Generic privilege — identical to `role` today, kept separate for future SoD divergence |

### Account handler

`AccountHandler.compute_delta` (introduced in Phase 19 H9) diffs `raw.accounts` against the `accounts` Postgres table on `(application_id, username)`. It emits the same five operations:

| Op | Meaning |
|---|---|
| `create` | Row exists in raw, absent in PG |
| `update` | Row in both; one of `email`, `status`, `is_privileged`, `mfa_enabled` differs |
| `revoke` | Row in PG, absent in raw — sets `status = deleted` on apply |
| `reactivate` | Row in PG with `status = deleted`, present in raw — flips back |
| `noop` | Row in both, no field drift |

Apply for the `account` entity type is owned by `apply_accounts_delta` inside `master_data_apply`.

### Handler contract

- Stateless.
- Does not flush or commit.
- Does not emit events.
- For access-fact runs, resolves resources via `ResourceService.ensure_resource_by_identity` — returns a `resource_id`, not a raw `resource_key`.

A handler failure does not stop the whole run — the row is counted in `facts_errored` (or `accounts_errored`) and processing continues. An unknown `artifact_type` means the artifact is skipped, not errored. Both skip paths emit an operational WARNING log via `engines.inventory_reconcile` to the `aurelion.logs` bus, carrying the row id and the reason. Skip warnings use `LogService.emit_safe` — a logging failure cannot abort the run.

Adding a new artifact type is a new handler file; the engine does not change.

## Run record key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `application_id` | UUID | Owning application |
| `entity_type` | string | `access_fact` or `account` |
| `status` | string | `running`, `pending_apply`, `dry_run_completed`, `applied`, `partially_applied`, `failed` |
| `mode` | string | `review`, `dry_run`, `auto_apply` (echoed from the request) |
| `observed_snapshot_id` | string | Iceberg snapshot id of the raw table read at run start |
| `current_snapshot_id` | string | Iceberg snapshot id of the target table at run start (null for `account` runs, since the target is PG) |
| `observed_batch_id` | UUID | Lake batch the diff observed (nullable until the run reaches the diff phase) |
| `created_count` / `updated_count` / `revoked_count` / `reactivated_count` / `unchanged_count` | int | Counts per op |
| `error` | string | Populated on `failed`; null otherwise |
| `created_at` / `started_at` / `finished_at` | datetime | Lifecycle timestamps |

## Delta item key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `run_id` | UUID | FK to the run |
| `entity_type` | string | `access_fact` or `account` — denormalised from the run for cross-run queries |
| `status` | string | `create`, `update`, `revoke`, `reactivate`, `unchanged` |
| `subject_id` / `account_id` | UUID | XOR for `access_fact` — exactly one is set; null for `account` runs |
| `resource_id` | UUID | Target resource (`access_fact` only) |
| `action_slug` | string | One of the seeded action slugs (`access_fact` only) |
| `effect` | string | `allow` or `deny` (`access_fact` only) |
| `valid_from` / `valid_until` | datetime | Validity window (nullable) |
| `created_at` | datetime | Used as the keyset pagination cursor |
| `subject_display`, `account_display`, `resource_display`, `application_code`, `application_name`, `change_summary` | string | Read-only display fields populated by `batch_*_display` helpers; nullable, fall back to UUID when no display value is available |

The display fields above are filled in by `display_lookups.py` on read — they are not stored on the row. Phase 19 H5 added them so list views can render human-readable strings without N+1 lookups; H6 fixed the underlying subject resolver to walk `subjects.id → employees | nhis → persons`.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/inventory-reconciles/runs` | Trigger a run |
| `GET`  | `/api/v0/inventory-reconciles/runs/{id}` | Get run record |
| `GET`  | `/api/v0/inventory-reconciles/runs/{id}/delta-items` | List delta items of one run (cursor-paginated) |
| `GET`  | `/api/v0/inventory-reconciles/delta-items` | Cross-run flat list of delta items |
| `GET`  | `/api/v0/inventory-reconciles/delta-items/count` | Cross-run count (same filters as the flat list) |
| `POST` | `/api/v0/inventory-reconciles/runs/{id}/apply` | Apply approved delta items (see [Apply](#apply-runs)) |

### POST /inventory-reconciles/runs

Request body:

```json
{
  "application_id": "550e8400-e29b-41d4-a716-446655440000",
  "entity_type": "access_fact",
  "mode": "review"
}
```

`entity_type` defaults to `access_fact` when omitted, preserving Phase 18 behaviour.

Response (`200`):

```json
{
  "id": "...",
  "application_id": "...",
  "entity_type": "access_fact",
  "status": "pending_apply",
  "mode": "review",
  "observed_snapshot_id": "...",
  "current_snapshot_id": "...",
  "observed_batch_id": "...",
  "created_count": 5,
  "updated_count": 2,
  "revoked_count": 1,
  "reactivated_count": 0,
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
| 409 | Another reconciliation run for the same `(application, entity_type)` is already in flight |
| 422 | Missing or invalid `application_id`, unknown `mode` value, unknown `entity_type` |

### GET /inventory-reconciles/runs/{id}

Returns the same `ReconciliationRunRead` shape as the POST response.

| Code | Condition |
|---|---|
| 200 | Run found |
| 404 | Run id unknown |

### GET /inventory-reconciles/runs/{id}/delta-items

Cursor-paginated. Keyset on `(created_at, id)` — stable across concurrent inserts (none happen after the run finishes anyway, but the ordering is deterministic).

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `status` | string | — | Filter by delta status (`create`, `update`, `revoke`, `reactivate`, `unchanged`) |
| `limit` | int | `100` | `1..1000` |
| `cursor` | string | — | Opaque cursor returned in `next_cursor` from the previous page |

Response:

```json
{
  "items": [ { "id": "...", "status": "create", "subject_display": "Иванов Иван", "...": "..." } ],
  "next_cursor": "eyJ0cyI6Ii4uLiIsImlkIjoiLi4uIn0"
}
```

Each item carries the H5 display fields documented in [Delta item key fields](#delta-item-key-fields).

When `next_cursor` is `null`, iteration is complete. Cursors are opaque base64url — see [API conventions / pagination](../api/overview.md#pagination).

| Code | Condition |
|---|---|
| 200 | Page returned (possibly empty) |
| 404 | Run id unknown |
| 422 | Unknown `status` value, `limit` out of range, malformed cursor |

### GET /inventory-reconciles/delta-items

Cross-run flat list. Phase 19 H7 added this endpoint so the Studio "Incoming" tab and the GUI can list pending delta items across the entire system without iterating per run.

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `status` | string | — | Filter by delta status (`create`, `update`, `revoke`, `reactivate`, `unchanged`) |
| `entity_type` | string | — | `access_fact` or `account` |
| `application_id` | UUID | — | Filter by application |
| `run_id` | UUID | — | Filter by run |
| `subject_ref` | UUID | — | Filter by subject (works for `access_fact` rows) |
| `limit` | int | `100` | `1..1000` |
| `cursor` | string | — | Opaque cursor from the previous page |

Response shape is identical to the per-run list (items carry display fields).

### GET /inventory-reconciles/delta-items/count

Same filters as the flat list; returns `{"count": <int>}`. Used by Studio badges and dashboard widgets.

## Apply runs

Apply takes the `approved` delta items of a reconciliation run and writes them to the target via `inventory_sync` (for `access_fact` runs) or `apply_accounts_delta` inside `master_data_apply` (for `account` runs). It is the only path that emits `inventory.access_fact.{created,updated,revoked,reactivated}` and the analogous `inventory.account.*` events.

A reconciliation run can be applied either implicitly (via `mode=auto_apply` on `POST /inventory-reconciles/runs`) or explicitly via `POST /inventory-reconciles/runs/{id}/apply`.

### Apply modes

| Mode | What it does |
|---|---|
| `auto_apply` | Apply every `approved` delta item belonging to the run |
| `manual_apply` | Same as `auto_apply` but invoked manually after a review |
| `selected_items` | Apply only the delta items listed in `item_ids`; all listed items must be in `approved` |
| `dry_run` | Run the mandatory crash-recovery preflight only — no writes, no events, all results marked `skipped` |

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

### POST /inventory-reconciles/runs/{id}/apply

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

`snapshot_ids` is the map of operation bucket to the Iceberg snapshot id produced by the lake write. Empty for `dry_run` and for `account` runs (which write to PG, not Iceberg).

| Code | Condition |
|---|---|
| 200 | Apply finished (status reflects outcome: `completed`, `partially_applied`, or `failed` with details in `error`) |
| 404 | Reconciliation run not found |
| 409 | An apply run for this reconciliation run is already in `running`, `completed`, or `partially_applied` |
| 422 | Invalid `mode`, missing `item_ids` for `selected_items`, or one of the listed items is not in `approved` |

### Concurrency

Manual apply does not re-acquire the per-`(application, entity_type)` advisory lock taken by reconciliation. Concurrency is enforced at the apply-run level: a second `POST /apply` for the same `reconciliation_run_id` while a previous apply run is still active (or already finished successfully) returns `409`. Crash recovery between row-level writes is handled by the mandatory `preflight_recover_already_written` step, which runs first on every apply call regardless of mode.

## Events

Each run emits domain events on `aurelion.events`:

| `event_type` | When | Key payload fields |
|---|---|---|
| `reconciliation.run.started` | After the run row is persisted, before the diff is computed | `run_id`, `application_id`, `entity_type`, `mode`, `correlation_id` |
| `reconciliation.delta.created` | After delta items are persisted, on success | `run_id`, `application_id`, `entity_type`, counts, `observed_snapshot_id`, `current_snapshot_id` |
| `reconciliation.run.completed` | After the run reaches its terminal success status | `run_id`, `application_id`, `entity_type`, `status`, counts |
| `reconciliation.run.failed` | When the pipeline raises | `run_id`, `application_id`, `entity_type`, `error` |

A failed run emits `run.started` followed by `run.failed`. `delta.created` and `run.completed` are not emitted on failure.

When the run is applied (either via `mode=auto_apply` or via `POST /runs/{id}/apply`), `inventory_sync` additionally emits one of `inventory.access_fact.{created,updated,revoked,reactivated}` per applied delta item for `access_fact` runs; account runs emit the analogous `inventory.account.*` events. Each payload carries `delta_item_id`, `snapshot_id` (null for account runs), and `reconciliation_run_id`. See [Events and Logs](../concepts/events.md) for envelope shape and the access-fact payload contract.

## CLI

```bash
al inventory-reconcile run --application-id <uuid>
al inventory-reconcile run --application-id <uuid> --entity-type account
```

Phase 19 H3 removed the legacy `al reconciliation run` and `al app reconcile run` commands — they pointed at the dead `/reconciliation/...` URL.

CLI flags for `mode` and the new GET endpoints land in a later phase; today the CLI defaults to `review` and `entity_type=access_fact`.

Exit code 0 = run completed. Exit code 1 = application not found, conflict, or other HTTP error.
