# Person

The reusable human profile root. Every Employee is backed by a Person. A Person can exist without an Employee (e.g. a contractor not yet in the system as a canonical identity).

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `external_id` | string | Identifier from the source system — **unique**, idempotency key for bulk upsert |
| `description` | string | Display label (stores `full_name` from bulk requests) |

Extensible via key-value attributes.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/persons` | Create a person |
| `POST` | `/api/v0/persons/bulk` | Bulk upsert up to 500 persons by `external_id` (idempotent) |
| `GET` | `/api/v0/persons` | Paginated list, ordered by `external_id ASC`. `limit` and `offset` are **required**. |
| `GET` | `/api/v0/persons/{id}` | Get by ID |
| `GET` | `/api/v0/persons/{id}/attributes` | List attributes |
| `POST` | `/api/v0/persons/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/persons/{id}/attributes/{key}` | Remove attribute |

### `GET /api/v0/persons`

Strict pagination — there are no defaults.

| Query param | Type | Range | Required |
|---|---|---|---|
| `limit` | int | `1 <= limit <= 1000` | yes |
| `offset` | int | `offset >= 0` | yes |

Missing or out-of-range values return `422`.

Response envelope (the only shape this endpoint returns):

```json
{
  "items": [
    {
      "id": "aaaa0000-0000-0000-0000-000000000001",
      "external_id": "emp-001",
      "description": "Jane Doe"
    }
  ],
  "total": 1,
  "limit": 1000,
  "offset": 0
}
```

`total` is the unfiltered row count. `limit` and `offset` echo the validated params. Ordering is `external_id ASC` (UNIQUE — no ties).

REST clients receive `(limit, offset) -> one page`. There are no internal pagination loops anywhere in the platform.

## CLI

| Command | Description |
|---|---|
| `al persons list --limit <n> --offset <n>` | List one page. `--limit` defaults to `1000`, `--offset` to `0`; both are validated against the kernel range (`1..1000`, `0..`). Output is the kernel envelope verbatim. |
| `al persons get <id>` | Get by ID |
| `al persons attributes <id>` | List attributes |

Create, update, and delete are API-only.
