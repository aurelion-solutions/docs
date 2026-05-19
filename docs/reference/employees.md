# Employee

The canonical internal human identity. Policies, access facts, and reconciliation rules all operate on Employees. Backed by a Person. An Employee can be bound to an org unit via `org_unit_id`; the product-side "internal vs contractor" partition reads `org_unit.is_internal` through that link.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `person_id` | UUID | FK to Person |
| `org_unit_id` | UUID \| null | FK to Org Unit; `ON DELETE SET NULL`. Kernel does not constrain the target's `is_internal` — that policy lives in product UI. |
| `is_locked` | boolean | Blocks access when true; checked by PDP |
| `description` | string | Display label |

Extensible via key-value attributes. Common attribute keys used by the PDP: `employment_status`, `department`, `mfa_enrolled`, `risk_score`.

See [Identity Model](../concepts/identity-model.md#internal-vs-external-org-units) for how `org_unit_id` ties an employee into the internal-vs-external partition, and [Org Unit](org-units.md) for the org-unit shape itself.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/employees` | Create an employee. Creates a Subject row automatically (`kind=employee`). |
| `POST` | `/api/v0/employees/bulk` | Bulk upsert employees by `person_external_id` (returns 422 if any external id is unknown). Creates a Subject row per resulting employee (`kind=employee`). |
| `GET` | `/api/v0/employees` | Paginated list, ordered by `id ASC`. `limit` and `offset` are **required**. |
| `GET` | `/api/v0/employees/{id}` | Get by ID |
| `PATCH` | `/api/v0/employees/{id}` | Update (`is_locked`, `description`) |
| `GET` | `/api/v0/employees/{id}/attributes` | List attributes |
| `POST` | `/api/v0/employees/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/employees/{id}/attributes/{key}` | Remove attribute |

### `POST /api/v0/employees`

Request body:

```json
{
  "person_id": "aaaa0000-0000-0000-0000-000000000001",
  "description": "Jane Doe",
  "org_unit_id": "cccc0000-0000-0000-0000-000000000003"
}
```

| Field | Required | Notes |
|---|---|---|
| `person_id` | yes | Must reference an existing Person. Unknown id → `404` `"Person not found"`. |
| `description` | no | |
| `org_unit_id` | no | If non-null, must reference an existing Org Unit. Unknown id → `404` `"Org-unit not found"`. The check is a precheck, not an FK error translation. Kernel accepts both `is_internal=true` and `is_internal=false` targets; any "contractor-only" restriction is a product-layer UI policy. |

| Status | Meaning |
|---|---|
| 201 | Created; response carries the assigned `id` and the supplied `org_unit_id` (or `null`) |
| 404 | `person_id` or `org_unit_id` references a missing row |
| 422 | Request validation error |

Emits `inventory.employee.created`. The event payload carries `employee_id`, `person_id`, `is_locked`, `description`, and `org_unit_id` (stringified UUID or `null`). A matching Subject row is created in the same transaction and emits `inventory.subject.created` (see [Subject](subjects.md#auto-creation)).

### `GET /api/v0/employees`

Strict pagination — there are no defaults.

| Query param | Type | Range | Required |
|---|---|---|---|
| `limit` | int | `1 <= limit <= 1000` | yes |
| `offset` | int | `offset >= 0` | yes |

Missing or out-of-range values return `422`. Calling without both params is a contract error, not a convenience to be defaulted.

Response envelope (the only shape this endpoint returns):

```json
{
  "items": [
    {
      "id": "bbbb0000-0000-0000-0000-000000000002",
      "person_id": "aaaa0000-0000-0000-0000-000000000001",
      "is_locked": false,
      "description": "Jane Doe",
      "org_unit_id": "cccc0000-0000-0000-0000-000000000003"
    }
  ],
  "total": 1,
  "limit": 1000,
  "offset": 0
}
```

`total` is the unfiltered row count. `limit` and `offset` echo the validated params. Ordering is `id ASC` (UUID primary key — stable but opaque; consumers that need a human-meaningful order sort client-side after paging).

REST clients receive `(limit, offset) -> one page`. There are no internal pagination loops anywhere in the platform — each call returns one page of up to 1000 rows.

### `GET /api/v0/employees/{id}`

Returns one row, including `org_unit_id`.

| Status | Meaning |
|---|---|
| 200 | Found |
| 404 | No row with this `id` |

## CLI

| Command | Description |
|---|---|
| `al employees list --limit <n> --offset <n>` | List one page. `--limit` defaults to `1000`, `--offset` to `0`; both are validated against the kernel range (`1..1000`, `0..`). Output is the kernel envelope verbatim. |
| `al employees get <id>` | Get by ID |
| `al employees attributes <id>` | List attributes |

Create, update, and attribute management are API-only.
