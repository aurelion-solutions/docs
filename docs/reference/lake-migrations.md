# Lake Migration

A `LakeMigrationRun` is the operator-triggered, resumable, idempotent job that copies existing PostgreSQL contents of `access_artifacts` and `access_facts` into the Iceberg lake while preserving identity and lifecycle columns. It is the bridge that makes flipping `LAKE_ARTIFACTS_WRITE_BACKEND` from `pg` to `iceberg` safe.

The slice owns one PG table (`lake_migration_runs`) plus a thin REST surface; the actual writes go through `lake_batches` (provenance) and the Iceberg tables `raw.access_artifacts` and `normalized.access_facts`. For `access_facts`, every migrated row is also recorded as a synthetic `ReconciliationDeltaItem` with `reason='pg_migration'` so the Iceberg fact row carries a real `reconciliation_delta_item_id`.

For the operational procedure (preflight, parity check, backend flip), see [Lake migration runbook](../operations/lake-migration-runbook.md). For the CLI client, see [`al lake`](../cli/lake.md).

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `dataset` | enum | `access_artifacts` or `access_facts` |
| `status` | enum | `pending`, `running`, `completed`, `failed`, `cancelled` |
| `batch_size` | int | Streaming batch size (default `5000`) |
| `rows_read` | bigint | Source rows fetched from PG |
| `rows_written` | bigint | Rows appended to Iceberg (excludes idempotent skips) |
| `last_processed_id` | UUID | Checkpoint cursor; `WHERE id > last_processed_id` on resume |
| `started_at` | datetime | Set when status moves to `running` |
| `finished_at` | datetime | Set on terminal state |
| `error` | string | Failure reason; populated when `status='failed'` |
| `lake_batch_id` | UUID | FK to `lake_batches`; carries the latest snapshot id and merged metadata |
| `synthetic_run_id` | UUID | Soft ref to `reconciliation_runs.id` for `access_facts` runs; `null` for `access_artifacts` |
| `metadata_json` | JSON | Free-form provenance; merged on resume |
| `created_at` | datetime | Row creation timestamp |

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/lake-migrations` | Start a migration. Non-blocking; persists `pending` row(s), schedules `BackgroundTasks`, returns 202. |
| `GET` | `/api/v0/lake-migrations/{id}` | Get a single run. Used for polling progress. |
| `GET` | `/api/v0/lake-migrations` | List runs with `status`, `dataset`, `cursor`, `page_size` filters. |

### `POST /lake-migrations`

Request body:

```json
{
  "dataset": "access_artifacts",
  "batch_size": 5000
}
```

Optional query parameter `?resume=<run_id>` continues an existing run instead of starting a fresh one. Resume requires the existing run's `dataset` to match the request body and its status to be in `{pending, running, failed, cancelled}` — completed runs cannot be resumed.

`dataset` accepts:

| Value | Behavior |
|---|---|
| `access_artifacts` | One run; returns a single `LakeMigrationRunRead`. |
| `access_facts` | One run; returns a single `LakeMigrationRunRead`. Creates a synthetic `ReconciliationRun`. |
| `all` | Two runs created and scheduled sequentially (`access_artifacts` then `access_facts`); returns a JSON array of two `LakeMigrationRunRead`. |

Response (single dataset):

```json
{
  "id": "8d3a1c70-22a9-4e6f-8c4f-9b1f2e3d4a5b",
  "dataset": "access_artifacts",
  "status": "pending",
  "batch_size": 5000,
  "rows_read": 0,
  "rows_written": 0,
  "last_processed_id": null,
  "lake_batch_id": "f4a5b6c7-d8e9-...",
  "synthetic_run_id": null,
  "started_at": null,
  "finished_at": null,
  "error": null,
  "created_at": "2026-04-27T10:30:00Z"
}
```

### `GET /lake-migrations/{id}`

Returns the same `LakeMigrationRunRead` shape. Poll this endpoint to observe progress — `rows_read`, `rows_written`, and `last_processed_id` are updated once per batch.

### `GET /lake-migrations`

Cursor-paginated list. Default ordering is `created_at DESC, id DESC`.

| Query param | Type | Notes |
|---|---|---|
| `status` | enum | Optional filter |
| `dataset` | enum | Optional filter |
| `page_size` | int | Default 50 |
| `cursor` | string | Opaque token from a previous response |

Response:

```json
{
  "items": [ { "id": "...", "dataset": "...", "status": "...", "...": "..." } ],
  "next_cursor": "eyJjcmVhdGVkX2F0Ijoi..."
}
```

When `next_cursor` is `null`, iteration is complete.

### Errors

| Code | Condition |
|---|---|
| 202 | Run accepted; background job scheduled |
| 404 | Run not found (`GET /{id}`) |
| 409 | Another run for the same dataset is already `running` (advisory-lock conflict), or `?resume=` targets a `completed` run |
| 422 | Unknown `dataset`, or `?resume=` dataset mismatch |

## Idempotency

Re-running a migration on the same source data is safe. Four layers prevent duplicates:

1. **Pre-write batch check** queries Iceberg for existing IDs in the batch and skips them. `rows_read` still increments; `rows_written` does not. A `lake_migration.batch_skipped_idempotent` log fires.
2. **Cursor resumability** uses `WHERE id > :last_processed_id` so a resumed run never re-reads acknowledged batches.
3. **Synthetic delta-item idempotency** (facts only) is enforced by a partial unique index on `reconciliation_delta_items(reason, existing_fact_id) WHERE reason='pg_migration'`.
4. **Lake-batch reuse** updates the existing `lake_batches` row on resume rather than creating a new one.

## Provenance

For `access_facts`, every migrated fact gets a synthetic `ReconciliationDeltaItem` with:

- `reason = 'pg_migration'`
- `operation = 'create'`
- `status = 'applied'`
- `applied_at = source_fact.created_at` (no `now()` drift)
- `existing_fact_id = fact.id`
- `before_json = null`
- `after_json` — a fixed-shape minimum-traceability snapshot (`origin`, `fact_id`, `subject_id`, `account_id`, `resource_id`, `action_id`, `effect`, `valid_from`, `valid_until`, `is_active`, `observed_at`, `created_at`, `revoked_at`, `application_id_denorm`, `subject_kind_denorm`)

The synthetic `ReconciliationRun` has `application_id = NULL` and `metadata_json` carrying both `origin='pg_migration'` and `lake_migration_run_id`.

For `access_artifacts`, no synthetic delta items are produced — artifact identity is preserved directly into Iceberg via `lake_batches`.

## Events

This entity emits **zero domain events**. Migration is observable via:

- `LogService` events: `lake_migration.run_started`, `lake_migration.batch_completed`, `lake_migration.batch_skipped_idempotent`, `lake_migration.run_completed`, `lake_migration.run_failed`
- `GET /api/v0/lake-migrations/{id}` polling

Rationale: no projection consumes a migration batch, and `inventory.access_fact.*` events are owned exclusively by `SyncApplyService`. Re-emitting them here would re-trigger the EAS projection for already-projected rows.

## CLI

| Command | Description |
|---|---|
| `al lake migrate-from-pg` | Start a migration and poll until terminal. See [CLI reference](../cli/lake.md). |
