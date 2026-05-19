# Org Unit

An organisational unit (department, team, division). Org units form a self-referential tree via `parent_id` and carry a platform-level membership flag, `is_internal`, that splits the tree into "managed identity space" nodes and external-party nodes.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `external_id` | string | Stable identifier from the source system; UNIQUE |
| `name` | string | Human-readable label |
| `parent_id` | UUID \| null | Self-reference; `NULL` for root nodes; `ON DELETE SET NULL` |
| `is_internal` | boolean | `true` = part of the managed identity space, `false` = external party. Default `true`. Per-tree invariant (see below). |
| `description` | string \| null | Free-form operator note for external companies. Not populated for internal rows. |

`is_internal` is a thin "ours vs not ours" flag. HR-style concepts — contractor companies, engagement dates, contract owner, end-of-engagement — do **not** live here; they live in the product layer. See [Identity Model](../concepts/identity-model.md#internal-vs-external-org-units) for the rationale.

## Per-tree `is_internal` invariant

A database trigger (`org_units_assert_is_internal_consistency`, function in `_trigger_sql.py`) enforces that every node in a connected org-unit tree shares the same `is_internal` value.

The trigger fires `BEFORE INSERT OR UPDATE OF parent_id, is_internal` on every row:

- **Parent check** — when the row has a parent, the parent's `is_internal` must equal the row's new value. Runs unconditionally whenever `NEW.parent_id IS NOT NULL`, so even an `is_internal`-only flip on a non-root node is checked against the parent.
- **Children check** — on `UPDATE`, if `is_internal` changed, no existing child may still hold the old value.

Violations raise `SQLSTATE 23514` (`check_violation`).

### Subtree flips are not supported via plain UPDATE

Because the parent-side check fires on every UPDATE of a non-root node, a single-row UPDATE cannot flip `is_internal` on a node independently of its parent, and a tree-wide multi-row UPDATE cannot proceed either (each row violates at the moment it is checked). **To convert a multi-node subtree from internal to external (or back), drop the subtree and recreate it with the new value.** This is intentional: switching a whole subtree is rare, and the trigger keeps the much-more-common single-node operations safe without a coordinator.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/org-units` | Paginated list, ordered by `external_id ASC`. `limit` and `offset` are **required**. |
| `POST` | `/api/v0/org-units/bulk` | Lake-first bulk ingest (writes `raw.org_units` in Iceberg) |
| `POST` | `/api/v0/org-units` | Create one external company (`is_internal=false`) |
| `GET` | `/api/v0/org-units/{id}` | Read one row by `id` |
| `PATCH` | `/api/v0/org-units/{id}` | Update `name` and/or `description` on an external row |
| `DELETE` | `/api/v0/org-units/{id}` | Delete an external row |

### `GET /api/v0/org-units`

Strict pagination — there are no defaults.

| Query param | Type | Range | Required |
|---|---|---|---|
| `limit` | int | `1 <= limit <= 1000` | yes |
| `offset` | int | `offset >= 0` | yes |

Missing or out-of-range values return `422`. Calling without both params is a contract error, not a convenience to be defaulted.

Response envelope (the entire API — there is no other shape):

```json
{
  "items": [
    {
      "id": "…",
      "external_id": "ENG",
      "name": "Engineering",
      "parent_id": null,
      "description": null,
      "is_internal": true
    }
  ],
  "total": 1,
  "limit": 1000,
  "offset": 0
}
```

`total` is the unfiltered row count. `limit` and `offset` echo the validated params. Ordering is stable: `external_id ASC` with `external_id` UNIQUE — no ties.

Every list item carries `parent_id` (UUID or `null` for roots), so clients reconstruct the org-unit tree from a single page sequence without follow-up `GET /org-units/{id}` calls. `description` is `null` for internal rows and free-form text on external rows.

REST clients receive `(limit, offset) -> one page`. There are no internal pagination loops anywhere in the platform.

### `POST /api/v0/org-units/bulk`

Lake-first ingest. The request body accepts `is_internal` per item for forward compatibility, but the lake-write path silently drops it: the `raw.org_units` Iceberg schema has no `is_internal` column. This is a permanent design property — external org units never originate from connectors or the lake.

To create or maintain external (`is_internal=false`) org units, use the operator UI. They are never reconciled from connectors and never land in the data lake.

Response:

```json
{ "row_count": 12, "snapshot_id": 8412034, "backend": "iceberg" }
```

| Status | Meaning |
|---|---|
| 200 | Snapshot written |
| 422 | Request validation error (e.g. duplicate `external_id`, self-referential parent, item count out of `[1, 500]`) |
| 502 | Lake write failure |
| 503 | Lake backend not configured |

### Single-row CRUD (external companies only)

Four endpoints manage external org units (`is_internal=false`) one row at a time. Internal rows are reconcile-managed via [`POST /api/v0/org-units/bulk`](#post-apiv0org-unitsbulk) and are not writable through these endpoints. None of the four endpoints emit events; the [`inventory.org_unit.bulk_upserted`](../concepts/events.md) event is emitted only by the bulk path.

Status mapping is uniform: `404` for an unknown `id`, `409` when the row exists but its state forbids the operation (i.e. it is internal), `422` for input validation.

#### `POST /api/v0/org-units`

Create one external company.

Request body:

```json
{
  "external_id": "ACME",
  "name": "Acme Corp",
  "parent_id": null,
  "description": "Primary contractor for the North America region."
}
```

| Field | Required | Notes |
|---|---|---|
| `external_id` | yes | UNIQUE across all org units |
| `name` | yes | |
| `parent_id` | no | If non-null, must reference another external row. Pointing at an internal row → `422`. |
| `description` | no | |
| `is_internal` | no | If supplied, must be `false`. `true` → `422`. Omitting it is treated as `false`. |

Response: `201` with the created row, including the assigned `id`.

| Status | Meaning |
|---|---|
| 201 | Created |
| 422 | Validation error (`is_internal=true`, duplicate `external_id`, `parent_id` points at an internal row or missing row) |

#### `GET /api/v0/org-units/{id}`

Returns one row in the same shape as items in the list envelope, plus `description`.

| Status | Meaning |
|---|---|
| 200 | Found |
| 404 | No row with this `id` |

#### `PATCH /api/v0/org-units/{id}`

Update `name` and/or `description`. Both fields are optional; an empty body is rejected. `external_id`, `parent_id`, and `is_internal` are immutable through this endpoint — sending any of them (or any other key) is a `422` (`extra='forbid'`).

| Status | Meaning |
|---|---|
| 200 | Updated; returns the new row |
| 404 | No row with this `id` |
| 409 | Row exists but `is_internal=true` |
| 422 | Empty body, unknown field, or invalid value |

#### `DELETE /api/v0/org-units/{id}`

Delete one external row. Any `employees.org_unit_id` pointing at the deleted row is set to `NULL` by the FK (`ON DELETE SET NULL`); no employees are deleted.

| Status | Meaning |
|---|---|
| 204 | Deleted |
| 404 | No row with this `id` |
| 409 | Row exists but `is_internal=true` |

## CLI

None. Internal org units are managed through bulk ingest (connectors and importers). External org units are managed through the operator UI, which calls the single-row CRUD endpoints above.

## See also

- [Identity Model](../concepts/identity-model.md) — where internal vs external org units sits in the platform model
- [Reconciliation](../concepts/reconciliation.md#lake-first-for-master-data) — the lake-first pipeline that feeds internal org units
