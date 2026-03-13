# Ownership Assignment

Records who owns a Resource or Account, and in what capacity. Ownership is used for access review routing and accountability. Assignments are immutable — to change ownership, delete and recreate.

Each assignment targets either a Resource or an Account, never both.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `subject_id` | UUID | The owner (FK to Subject) |
| `resource_id` | UUID | Target resource (XOR with `account_id`) |
| `account_id` | UUID | Target account (XOR with `resource_id`) |
| `kind` | enum | `primary`, `secondary`, `technical` |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/ownership-assignments` | List, filter by `subject_id`, `resource_id`, `account_id`, `kind` |
| `GET` | `/api/v0/ownership-assignments/{id}` | Get by ID |
| `POST` | `/api/v0/ownership-assignments` | Create |
| `DELETE` | `/api/v0/ownership-assignments/{id}` | Delete |

## CLI

| Command | Description |
|---|---|
| `al inventory ownership-assignments list` | List all assignments |
| `al inventory ownership-assignments list --subject <id>` | Filter by owner |
| `al inventory ownership-assignments list --resource <id>` | Filter by resource |
| `al inventory ownership-assignments list --kind <kind>` | Filter by kind |
| `al inventory ownership-assignments get <id>` | Get by ID |
| `al inventory ownership-assignments create --subject <id> --kind <kind> --resource <id>` | Assign resource owner |
| `al inventory ownership-assignments create --subject <id> --kind <kind> --account <id>` | Assign account owner |
| `al inventory ownership-assignments delete <id>` | Delete |
