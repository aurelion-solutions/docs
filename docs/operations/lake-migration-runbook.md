# Lake Migration Runbook

Procedure for moving existing PostgreSQL contents of `access_artifacts` and `access_facts` into the Iceberg lake, then flipping `LAKE_ARTIFACTS_WRITE_BACKEND` so all *new* artifact writes route to Iceberg.

The migration is **operator-driven**. It is idempotent and resumable, but it is **not** automatic — nothing in the kernel flips the backend or starts a run on its own.

For the API and entity reference, see [Lake migration](../reference/lake-migrations.md). For the client, see [`al lake`](../cli/lake.md).

## When to run

Run this when you intend to switch `LAKE_ARTIFACTS_WRITE_BACKEND` from `pg` to `iceberg` in production. Until you do, the gate stays on `pg`, the Iceberg tables sit empty, and every existing PG row is invisible to the lake-backed read path.

Do **not** run it:

- During heavy ingest. The migration uses a server-side cursor and is read-only against PG, but the synthetic `ReconciliationRun` and `lake_batches` rows commit while the job runs. Plan a maintenance window where reconciliation is quiet.
- Without a recent PG backup. The migration is non-destructive — PG rows are not deleted — but flipping the backend gate is the inflection point after which new writes diverge between the two stores. Have a recovery plan.

## Capacity ceiling

`BackgroundTasks` carries the migration in-process. The documented ceiling is **roughly 10 million combined rows** across `access_artifacts` and `access_facts`. Beyond that, the riskiest assumption is that the request worker stays alive long enough to finish — if the host OOMs or restarts mid-run, batch state survives in PG and the run is resumable, but you should still size the host accordingly. If you sit above the ceiling, escalate before proceeding; the out-of-process worker is a deferred phase.

## Preflight

1. **Backend gate is on `pg`.** Confirm `LAKE_ARTIFACTS_WRITE_BACKEND` is unset or `pg`. If it is already `iceberg`, the migration will still run, but you no longer have a clean before-state to compare against.

2. **Iceberg tables exist.** The platform API runtime provisions `raw.access_artifacts` and `normalized.access_facts` on startup. Confirm via Swagger or by running:

   ```bash
   psql "$DATABASE_URL" -c "SELECT 1 FROM iceberg_catalog.iceberg_tables LIMIT 1"
   ```

3. **Migrations applied.** Run `uv run alembic upgrade head` from `aurelion-kernel/` to ensure the `lake_migration_runs` table and the `reconciliation_delta_items` partial unique index are present.

4. **Row counts captured.** Take a baseline so the post-run parity check has something to compare:

   ```bash
   psql "$DATABASE_URL" -c "SELECT count(*) FROM access_artifacts"
   psql "$DATABASE_URL" -c "SELECT count(*) FROM access_facts"
   ```

5. **No live migration for the same dataset.** A `pg_try_advisory_xact_lock` keyed on `hash('lake_migration', dataset)` rejects concurrent runs with HTTP 409. If `GET /api/v0/lake-migrations?status=running` returns a row, wait or cancel it before starting a new one.

## Run

From a host that has the CLI and points at the kernel:

```bash
al lake migrate-from-pg --dataset all --batch-size 5000 --poll-interval 2.0
```

`--dataset all` schedules `access_artifacts` first, then `access_facts`. The CLI polls both runs and exits 0 only when both reach `completed`. Progress (`rows_read`, `rows_written`, `last_processed_id`) streams to stderr; final counts go to stdout as JSON.

To run datasets independently:

```bash
al lake migrate-from-pg --dataset access_artifacts
al lake migrate-from-pg --dataset access_facts
```

`access_facts` does not require `access_artifacts` to have completed first — facts carry their own identity into Iceberg and the synthetic delta items are independent of artifact migration. In practice running them in order keeps the provenance chain coherent.

## Resume

If the kernel process dies, the host OOMs, or the CLI is interrupted, the run row stays in PG with its `last_processed_id` checkpoint and `status` left at `running` (or `failed` if the worker caught the exception). To continue:

```bash
al lake migrate-from-pg --resume <run_id>
```

The CLI sends `POST /api/v0/lake-migrations?resume=<run_id>` with the original dataset. The service:

- Verifies the dataset matches and the status is not `completed`
- Resets `status='running'`, `started_at=now()`
- Keeps `last_processed_id`, `lake_batch_id`, and `synthetic_run_id`
- Merges (does not overwrite) `metadata_json` with a `resumed_at` entry

If you do not know the run id, list them:

```bash
al lake migrate-from-pg  # not the right command for listing — use the API directly:
curl "$AURELION_API_URL/api/v0/lake-migrations?status=failed"
```

## Parity check

After both runs complete, verify the lake matches PG before flipping the backend.

Row counts:

```bash
# PG
psql "$DATABASE_URL" -c "SELECT count(*) FROM access_artifacts"
psql "$DATABASE_URL" -c "SELECT count(*) FROM access_facts"

# Iceberg, via DuckDB session — use the platform API duckdb iceberg_scan
```

Spot-check identity preservation:

```sql
-- Same id should exist in both stores with the same created_at and observed_at.
SELECT id, created_at, observed_at FROM access_artifacts ORDER BY created_at LIMIT 5;
-- Compare against iceberg_scan('raw.access_artifacts')
```

Synthetic delta items (facts only):

```bash
psql "$DATABASE_URL" -c "
  SELECT count(*) FROM reconciliation_delta_items
  WHERE reason = 'pg_migration' AND status = 'applied'
"
# Should equal the count of access_facts rows migrated.
```

If counts disagree, **do not flip the backend**. Inspect `lake_migration.batch_skipped_idempotent` log entries — non-zero skip counts on a clean first run indicate either pre-existing Iceberg rows from a previous attempt (safe to ignore) or a bug (escalate).

## Backend flip

After parity is confirmed, set the env var on every replica that runs the platform API:

```bash
LAKE_ARTIFACTS_WRITE_BACKEND=iceberg
```

Restart the platform API runtime. From this point:

- All new `POST /api/v0/access-artifacts/bulk` writes route to Iceberg.
- All `GET /api/v0/access-artifacts` reads use DuckDB `iceberg_scan` with cursor pagination — `limit`/`offset` are ignored and `cursor` is required after the first page. See [Access Artifact reference](../reference/access-artifacts.md#get-access-artifacts-response-shape).
- Existing PG `access_artifacts` rows stay where they are, read-only. They are dropped in Phase 15 Step 16.

`LAKE_ARTIFACTS_WRITE_BACKEND` is a one-way migration gate. Flipping it back to `pg` after writes have landed in Iceberg leaves the lake-resident rows invisible to the API and re-routes new writes to PG — split-brain. If you need to roll back, restore from the pre-flip backup; do not flip the gate twice.

## Post-flip

- **Compaction.** Each migration batch produces one Iceberg snapshot. Multi-million-row runs leave hundreds of small data files behind. Run `al lake status --table raw.access_artifacts` (and `normalized.access_facts`) to inspect snapshot/file counts, then `al lake compact --table <name>` to trigger `rewrite_data_files`. See [`al lake`](../cli/lake.md).
- **Reconciliation re-run.** Not required. The synthetic `ReconciliationRun` already exists with `status='applied'` and migrated facts carry valid `reconciliation_delta_item_id` values. Reconciliation continues normally on the next ingest cycle.
- **PG drop.** Step 16 drops the `access_artifacts` and `access_facts` PG tables. Until then the rows stay readable but stale — only the Iceberg side receives new writes.

## Failure modes

| Symptom | Cause | Recovery |
|---|---|---|
| `POST /lake-migrations` returns 409 | Another run for the same dataset is `running`; advisory lock held | Wait for the running run to finish, or cancel it manually before starting a new one |
| `POST /lake-migrations?resume=<id>` returns 409 | Resume target is `completed` | Start a fresh run; you cannot resume a completed migration |
| `POST /lake-migrations?resume=<id>` returns 422 | Dataset in body does not match dataset on the existing run | Use the right dataset, or omit `resume=` and start fresh |
| Run stuck in `running` after a host crash | Worker died mid-batch; advisory lock released on transaction rollback, but status was last set to `running` before the crash | Resume by run id; the cursor picks up at the last committed checkpoint |
| `lake_migration.run_failed` with `error` populated | Iceberg append failed, denorm join missing rows, or PG read error | Read the `error` field, fix the root cause, then resume by run id |
| Iceberg snapshot count growing without compaction | Expected — one snapshot per batch | Run `al lake compact --table <name>` to trigger `rewrite_data_files` |
