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

## Auto-creation

Every principal has exactly one Subject. The kernel maintains that invariant automatically: whenever an Employee, NHI, or Customer is created — over HTTP, via bulk upsert, or by the `inventory_reconcile` engine's apply step — `SubjectService.ensure_for_principal(kind, principal_id)` runs in the same transaction and inserts the matching Subject row.

The helper is idempotent. If a Subject already binds the principal via the corresponding `principal_<kind>_id` FK, the existing row is returned and no event is emitted. A new row triggers `inventory.subject.created` exactly once.

`POST /api/v0/subjects` remains available for operators that need to mint a Subject by hand (for fixtures, support workflows, or recovery), but is rarely necessary in normal operation — the four principal-creating paths already cover it.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/subjects` | Create a Subject by hand (rarely needed — see Auto-creation) |
| `GET` | `/api/v0/subjects` | List subjects, filter by `kind` or `status` |
| `GET` | `/api/v0/subjects/{id}` | Get by ID |
| `PATCH` | `/api/v0/subjects/{id}` | Update status |
| `GET` | `/api/v0/subjects/{id}/attributes` | List attributes |
| `POST` | `/api/v0/subjects/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/subjects/{id}/attributes/{key}` | Remove attribute |

## CLI

| Command | Description |
|---|---|
| `al inventory subjects list` | List all subjects |
| `al inventory subjects list --kind <kind>` | Filter by kind |
| `al inventory subjects list --status <status>` | Filter by status |
| `al inventory subject <id>` | Get by ID (includes attributes) |

See the [Identity Model](../concepts/identity-model.md#subject-the-convergence-point) for how Subject relates to Employee, NHI, and Customer.
