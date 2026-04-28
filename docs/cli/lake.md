# CLI — Lake

Reference for `al` commands that drive the data-lake operational surface: `migrate-from-pg` (PG → Iceberg one-shot migration), `status` (per-table snapshot/file inspection), and `compact` (manual `rewrite_data_files` trigger).

All commands accept a global `--base-url` option (defaults to the configured platform URL) and emit JSON to stdout on success. Errors go to stderr with exit code `1` for API errors and `2` for client-side validation errors.

See also: [Lake migration reference](../reference/lake-migrations.md), [Lake migration runbook](../operations/lake-migration-runbook.md).

---

## `al lake migrate-from-pg`

Start a migration of existing PostgreSQL contents into the Iceberg lake, then poll until the run reaches a terminal state.

| Option | Description |
|---|---|
| `--dataset` | `all` (default) \| `access_artifacts` \| `access_facts` |
| `--batch-size` | Streaming batch size (default `5000`). Capped at the kernel's `LAKE_PG_ANY_ARRAY_MAX_SIZE` threshold. |
| `--resume` | Existing run UUID to resume. Mutually exclusive with starting a fresh run on a different dataset. |
| `--poll-interval` | Seconds between progress polls (default `2.0`). |
| `--base-url` | Platform API base URL. Falls back to `AURELION_API_URL`. |

Calls `POST /api/v0/lake-migrations` (with `?resume=<run_id>` when `--resume` is set), then polls `GET /api/v0/lake-migrations/{id}` every `--poll-interval` seconds.

### Behavior

- Progress (`rows_read`, `rows_written`, `last_processed_id`) streams to **stderr** during polling.
- Final counts emit to **stdout** as JSON when the run reaches a terminal state.
- Exit codes:
    - `0` — every polled run reached `completed`.
    - `1` — at least one run reached `failed` or `cancelled`, or the kernel returned an error response.
    - `2` — client-side validation error (e.g. invalid `--dataset` value).

### `--dataset all`

Submits a single `POST` with `dataset=all`, which the kernel expands into two runs scheduled sequentially (`access_artifacts` first, then `access_facts`). The CLI polls both run ids and only exits 0 when both reach `completed`. If either fails, the CLI exits 1 and the failed run id is reported on stderr.

### Examples

Run both datasets end-to-end:

```bash
al lake migrate-from-pg --dataset all --batch-size 5000 --poll-interval 2.0
```

Run only `access_artifacts`:

```bash
al lake migrate-from-pg --dataset access_artifacts
```

Resume after a host crash:

```bash
al lake migrate-from-pg --resume 8d3a1c70-22a9-4e6f-8c4f-9b1f2e3d4a5b
```

Drive against a non-default kernel:

```bash
al lake migrate-from-pg --dataset access_facts \
  --base-url https://kernel.staging.aurelion.io
```

### Sample output

Stderr (one line per poll, abbreviated):

```
[migration 8d3a1c70...] dataset=access_artifacts status=running rows_read=15000 rows_written=15000 last_processed_id=...
[migration 8d3a1c70...] dataset=access_artifacts status=running rows_read=20000 rows_written=20000 last_processed_id=...
[migration 8d3a1c70...] dataset=access_artifacts status=completed rows_read=24812 rows_written=24812
```

Stdout (final, on success):

```json
{
  "runs": [
    {
      "id": "8d3a1c70-22a9-4e6f-8c4f-9b1f2e3d4a5b",
      "dataset": "access_artifacts",
      "status": "completed",
      "rows_read": 24812,
      "rows_written": 24812,
      "started_at": "2026-04-27T10:30:01Z",
      "finished_at": "2026-04-27T10:34:18Z"
    },
    {
      "id": "f4a5b6c7-d8e9-1234-5678-90abcdef0123",
      "dataset": "access_facts",
      "status": "completed",
      "rows_read": 18203,
      "rows_written": 18203,
      "started_at": "2026-04-27T10:34:19Z",
      "finished_at": "2026-04-27T10:37:55Z"
    }
  ]
}
```

### Failure handling

| Situation | CLI behavior |
|---|---|
| Run terminates with `failed` | Exit 1; final stderr line includes `error=<reason>`; the run row is left in `failed` so it can be resumed. |
| Run terminates with `cancelled` | Exit 1. |
| Kernel returns 409 on submit (lock conflict or completed-resume) | Exit 1; error printed to stderr. |
| Kernel returns 422 on submit (unknown dataset / dataset mismatch on resume) | Exit 1; error printed to stderr. |
| Polling fails transiently | Polling retries on the next interval; persistent failures bubble out as exit 1. |

The CLI itself uses `typer.echo(..., err=True)` for stderr progress; that is **not** a kernel `LogService` call site (the CLI is a client, not a kernel runtime).

---

## `al lake status`

Print catalog and per-table snapshot metadata for all known Iceberg lake tables.

| Option | Description |
|---|---|
| `--base-url` | Platform API base URL. Falls back to `AURELION_API_URL`. |

Calls `GET /api/v0/lake/status` and prints the response as JSON to stdout. Exit `0` on success, `1` on API error.

Each table entry in the response contains: `namespace`, `name`, `current_snapshot_id`, `snapshot_count`, `last_updated_ms`.

```bash
al lake status
```

---

## `al lake compact`

Trigger compaction, snapshot expiry, and (gated) orphan-file cleanup for one or all lake tables.

| Option | Default | Description |
|---|---|---|
| `--table` | `all` | Table scope: `raw.access_artifacts`, `normalized.access_facts`, or `all`. |
| `--retention-days` | `7` | Snapshot retention window in days. |
| `--orphan-older-than-hours` | `24` | Skip orphan files newer than this age (hours). |
| `--target-file-size-mb` | `128` | Target compacted file size in MB. |
| `--base-url` | — | Platform API base URL. Falls back to `AURELION_API_URL`. |

Calls `POST /api/v0/lake/compaction` with the options in the request body, then prints the per-table result payload as indented JSON. The safety gate in the kernel skips `clean_orphan_files` when an active Sync/Apply run or recent ingest batches are detected; see the response `orphan_cleanup_skipped` field.

```bash
al lake compact
al lake compact --table raw.access_artifacts
al lake compact --table normalized.access_facts --target-file-size-mb 256
al lake compact --retention-days 14 --orphan-older-than-hours 48
```

Exit codes: `0` on success, `1` on API or connection error.
