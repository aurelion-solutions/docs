# CLI — Lake

Reference for `al` commands that drive the data-lake operational surface: `status` (per-table snapshot/file inspection) and `compact` (manual `rewrite_data_files` trigger).

All commands accept a global `--base-url` option (defaults to the configured platform URL) and emit JSON to stdout on success. Errors go to stderr with exit code `1` for API errors and `2` for client-side validation errors.

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
