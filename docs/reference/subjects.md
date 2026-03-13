# Subject

The unified principal abstraction. Points to exactly one Employee, NHI, or Customer. Used by the PDP, access facts, and audit log — anywhere the specific principal type should not matter.

Subject status is denormalized automatically when the underlying entity changes state.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `kind` | string | `employee`, `nhi`, or `customer` |
| `status` | string | `active`, `suspended`, `locked`, `terminated`, `deleted` |

Extensible via key-value attributes.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/subjects` | List subjects, filter by `kind` or `status` |
| `GET` | `/api/v0/subjects/{id}` | Get by ID |
| `PATCH` | `/api/v0/subjects/{id}` | Update status |
| `GET` | `/api/v0/subjects/{id}/attributes` | List attributes |
| `POST` | `/api/v0/subjects/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/subjects/{id}/attributes/{key}` | Remove attribute |

Subjects are created automatically when their underlying identity is created — there is no direct `POST /subjects`.

## CLI

| Command | Description |
|---|---|
| `al inventory subjects list` | List all subjects |
| `al inventory subjects list --kind <kind>` | Filter by kind |
| `al inventory subjects list --status <status>` | Filter by status |
| `al inventory subject <id>` | Get by ID (includes attributes) |
