# Data Lake

Batch-oriented storage for connector and staging data. Connectors write large result sets here instead of inline; the `lake_ref` result type in connector results references a batch by key.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `storage_provider` | string | Backend (e.g. `file`) |
| `dataset_type` | string | Type of records (e.g. `accounts`, `resources`) |
| `storage_key` | string | Key used to retrieve the payload from the provider |
| `row_count` | int | Number of records in the batch |
| `application_id` | UUID | Optional owning application |
| `task_id` | UUID | Optional originating task |

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/datalake/batches` | Create a batch (write records to the lake) |
| `GET` | `/api/v0/datalake/batches` | List batches with cursor pagination (`?limit=`, `?cursor=`) |
| `GET` | `/api/v0/datalake/batches/{id}` | Get batch metadata |
| `GET` | `/api/v0/datalake/batches/{id}/data` | Get batch payload (records) |
| `DELETE` | `/api/v0/datalake/batches/{id}` | Delete batch (metadata + payload) |

The list endpoint returns `{ "items": [...], "next_cursor": "<opaque>" | null }`. Pass `next_cursor` back as `?cursor=` to fetch the following page. Default `limit` is 50, max 200.

> **Breaking (April 2026):** `snapshot_id` on batch responses is now serialized as a **string** in JSON (Iceberg snapshot ids exceed JS `Number.MAX_SAFE_INTEGER`). The DB column remains a 64-bit integer; only the wire format changed. JS/TS clients must parse it as a string and not coerce to `Number`.

## CLI

| Command | Description |
|---|---|
| `al datalake batches create --storage-provider <p> --dataset-type <t> --records <json>` | Create a batch |
| `al datalake batches list [--limit <n>] [--cursor <token>]` | List batches with cursor pagination |
| `al datalake batches get <id>` | Get batch metadata |
| `al datalake batches data <id>` | Get batch records |
| `al datalake batches delete <id>` | Delete batch |

---

## Iceberg Operations

Operational endpoints for the PyIceberg-backed lake (`raw.access_artifacts`, `normalized.access_facts`). These are distinct from the legacy datalake/batches surface above.

### `GET /api/v0/lake/status`

Returns catalog metadata and per-table snapshot information.

**Response — `LakeStatusResponse`:**

| Field | Type | Description |
|---|---|---|
| `catalog_uri` | string | Iceberg catalog URI (credentials redacted) |
| `warehouse_uri` | string | Warehouse root URI |
| `storage_provider` | `"file"` \| `"s3"` | Storage backend |
| `tables` | `LakeTableStatus[]` | Per-table metadata, sorted by (namespace, name) |

**`LakeTableStatus` fields:**

| Field | Type | Description |
|---|---|---|
| `namespace` | string | Iceberg namespace (e.g. `raw`, `normalized`) |
| `name` | string | Table name (e.g. `access_artifacts`) |
| `current_snapshot_id` | integer \| null | Latest committed snapshot id |
| `snapshot_count` | integer | Total number of snapshots |
| `last_updated_ms` | integer \| null | Epoch-ms timestamp of last snapshot |

**Example response:**

```json
{
  "catalog_uri": "file:///data/iceberg",
  "warehouse_uri": "file:///data/warehouse",
  "storage_provider": "file",
  "tables": [
    {
      "namespace": "normalized",
      "name": "access_facts",
      "current_snapshot_id": 7240157923456,
      "snapshot_count": 14,
      "last_updated_ms": 1745740200000
    },
    {
      "namespace": "raw",
      "name": "access_artifacts",
      "current_snapshot_id": 6182034751209,
      "snapshot_count": 22,
      "last_updated_ms": 1745739900000
    }
  ]
}
```

### `POST /api/v0/lake/compaction`

Runs `compact_table` + `expire_old_snapshots` + (gated) `clean_orphan_files` for one or all tables.

**Request body — `LakeCompactionRequest`:**

| Field | Type | Default | Description |
|---|---|---|---|
| `table` | `"raw.access_artifacts"` \| `"normalized.access_facts"` \| `"all"` | `"all"` | Table scope |
| `retention_days` | integer | `7` | Snapshot retention window (days, >=1) |
| `orphan_older_than_hours` | integer | `24` | Age threshold for orphan cleanup (hours, >=1) |
| `target_file_size_mb` | integer | `128` | Target compacted file size (MB, >=16) |

**Response — `LakeCompactionResponse`:**

| Field | Type | Description |
|---|---|---|
| `tables` | `LakeTableCompactionResult[]` | Per-table compaction results |
| `orphan_cleanup_skipped` | boolean | `true` if orphan cleanup was skipped globally |
| `orphan_cleanup_skip_reason` | string \| null | Human-readable reason when skipped |

Each `LakeTableCompactionResult` includes: `namespace`, `name`, `files_before`, `files_after`, `bytes_before`, `bytes_after`, `compaction_snapshot_id`, `snapshots_removed`, `latest_snapshot_id`, `orphan_files_removed`, `orphan_bytes_freed`, `orphan_cleanup_skipped`, `orphan_cleanup_skip_reason`.

**Safety gate:** Before invoking `clean_orphan_files`, the kernel checks for active writes. Cleanup is skipped if any of the following is true:

- A `sync_apply_runs` row with `status = 'running'` exists.
- A `lake_batches` row has `created_at > now() - interval '2 * orphan_older_than_hours hours'`.

When the gate fires, `compact_table` and `expire_old_snapshots` still execute; only orphan cleanup is skipped. The response reflects this with `orphan_cleanup_skipped: true`.

**Example:**

```bash
curl -X POST http://localhost:8000/api/v0/lake/compaction \
  -H "Content-Type: application/json" \
  -d '{"table": "raw.access_artifacts", "retention_days": 7, "target_file_size_mb": 128}'
```

```json
{
  "tables": [
    {
      "namespace": "raw",
      "name": "access_artifacts",
      "files_before": 18,
      "files_after": 3,
      "bytes_before": 524288000,
      "bytes_after": 134217728,
      "compaction_snapshot_id": 8831029471234,
      "snapshots_removed": 6,
      "latest_snapshot_id": 8831029471234,
      "orphan_files_removed": 0,
      "orphan_bytes_freed": 0,
      "orphan_cleanup_skipped": false,
      "orphan_cleanup_skip_reason": null
    }
  ],
  "orphan_cleanup_skipped": false,
  "orphan_cleanup_skip_reason": null
}
```
