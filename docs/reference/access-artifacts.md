# Access Artifact

Append-only raw access evidence from connectors. Every piece of access data that enters Aurelion starts as an artifact. Artifacts are never modified or deleted — they are the permanent record of what connectors reported. Tombstoning marks an artifact inactive but keeps the row.

The `artifact_type` field determines which reconciliation handler processes the artifact.

The storage backend is selected by the `LAKE_ARTIFACTS_WRITE_BACKEND` migration gate (see [Platform API runtime](../operations/platform-api.md#configuration)). Under `pg` the artifacts live in PostgreSQL; under `iceberg` they live in the Iceberg `raw.access_artifacts` table and reads go through DuckDB `iceberg_scan`. The API contract is identical — `backend` is reported on bulk responses for diagnostics only.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `application_id` | UUID | FK to Application |
| `artifact_type` | string | Handler dispatch key (e.g. `role`, `acl_entry`, `db_grant`) |
| `external_id` | string | Identifier in the source system |
| `payload` | JSON | Raw data in source vocabulary |
| `effect` | string | `allow` or `deny` |
| `is_active` | boolean | False after tombstoning |
| `tombstoned_at` | datetime | Set when the artifact is tombstoned |
| `observed_at` | datetime | When the connector observed this access |
| `ingest_batch_id` | string | Batch this artifact arrived in |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/access-artifacts` | List, filter by `application_id`, `artifact_type`, `is_active`. Cursor-paginated. |
| `GET` | `/api/v0/access-artifacts/{id}` | Get by ID |
| `POST` | `/api/v0/access-artifacts/bulk` | Bulk upsert up to 10 000 artifacts in one call |
| `POST` | `/api/v0/access-artifacts/bulk-tombstone` | Bulk tombstone up to 10 000 artifacts by ID |

### `GET /access-artifacts` response shape

> **Breaking change (Phase 15 Step 6).** This endpoint previously returned a bare JSON array of artifacts. It now returns an `AccessArtifactCursorPage`:
>
> ```json
> {
>   "items": [ { "id": "...", "application_id": "...", "...": "..." } ],
>   "next_cursor": "eyJhcHBsaWNhdGlvbl9pZCI6Ii4uLiIsImxhc3Rfc2Vlbl9pZCI6Ii4uLiJ9"
> }
> ```
>
> Clients that previously did `for a in response.json()` must switch to `for a in response.json()["items"]`.

| Query param | Type | Notes |
|---|---|---|
| `application_id` | UUID | Optional filter |
| `artifact_type` | string | Optional filter |
| `is_active` | bool | Optional filter |
| `limit` | int (1–200, default 50) | Page size for the `pg` backend (offset pagination) |
| `offset` | int (default 0) | Offset for the `pg` backend |
| `cursor` | string | Opaque token for the `iceberg` backend (keyset pagination) |

Pagination semantics depend on the active backend:

- **`pg` backend** — offset pagination via `limit`/`offset`. `next_cursor` is always `null`.
- **`iceberg` backend** — keyset pagination via `cursor`. The first page omits `cursor`. Each response carries `next_cursor`; pass it back unchanged on the next request. When the server returns `next_cursor: null`, the iteration is complete. Page size is taken from `LAKE_READ_PAGE_SIZE` (default 1000, max 5000); `limit` and `offset` are ignored under `iceberg`. A malformed cursor returns 400 `invalid cursor`.

Cursors are opaque base64url-encoded JSON. Do not parse them; do not assume they are stable across server versions.

### `POST /access-artifacts/bulk`

Upserts artifacts by `(application_id, artifact_type, external_id)`. Existing rows with matching keys are updated; new rows are inserted. Routes through `AccessArtifactService.upsert_batch`; the `inventory.access_artifacts.batch_ingested` domain event is emitted exactly once per call by the ingest capability.

Request:

```json
{
  "ingest_batch_id": "9e1b3f7a-...",
  "correlation_id": "optional",
  "items": [
    {
      "application_id": "...",
      "artifact_type": "role",
      "external_id": "admin",
      "payload": { "...": "..." },
      "raw_name": "Admin",
      "effect": "allow",
      "valid_from": "2026-01-01T00:00:00Z",
      "valid_until": null,
      "observed_at": "2026-04-27T10:30:00Z"
    }
  ]
}
```

Response (200):

```json
{
  "row_count": 1,
  "snapshot_id": 4827193020384,
  "backend": "iceberg"
}
```

`snapshot_id` is the Iceberg snapshot id under the `iceberg` backend; `null` under `pg`.

### `POST /access-artifacts/bulk-tombstone`

Marks the listed artifact IDs inactive and stamps `tombstoned_at = observed_at`. The artifacts are not deleted.

Request:

```json
{
  "artifact_ids": ["...", "..."],
  "observed_at": "2026-04-27T10:30:00Z",
  "correlation_id": "optional"
}
```

Response (200):

```json
{
  "tombstoned_count": 2,
  "snapshot_id": 4827193020385,
  "backend": "iceberg"
}
```

### Errors

| Code | Condition |
|---|---|
| 400 | Invalid cursor token (GET only) |
| 422 | Batch exceeds 10 000 items, or item validation fails |
| 502 | Lake write failed (Iceberg snapshot commit error) |
| 503 | Lake backend not configured |

## Events

| Event type | When | Payload |
|---|---|---|
| `inventory.access_artifacts.batch_ingested` | One per successful bulk upsert or bulk tombstone | `batch_id`, `ingested_count`, `tombstoned_count`, `snapshot_id`, `application_id`, `backend` |

Emitted from `capabilities.ingest.service` (single emit site). Bulk routes never emit directly.

## CLI

| Command | Description |
|---|---|
| `al inventory artifacts list` | List all artifacts |
| `al inventory artifacts list --application-id <id>` | Filter by application |
| `al inventory artifacts list --artifact-type <type>` | Filter by type |
| `al inventory artifacts get <id>` | Get by ID |

> Bulk upsert / tombstone CLI commands are deferred to Phase 15 Step 17.
