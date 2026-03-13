# Resource

A normalized access target — a repository, database, role, file share, or any object that access facts point to. Resources are scoped to an Application by `(resource_type, resource_key)` and are resolve-or-created during normalization and reconciliation.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `application_id` | UUID | FK to Application |
| `external_id` | string | Natural key within the application |
| `resource_type` | string | Kind of resource (e.g. `repository`, `database`, `role`) |
| `resource_key` | string | Unique identifier within the application + type |
| `privilege_level` | enum | `none`, `read`, `write`, `admin` |
| `environment` | enum | `production`, `staging`, `dev` |
| `data_sensitivity` | enum | `public`, `financial`, `pii` |

Extensible via key-value attributes.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/resources` | Create a resource |
| `GET` | `/api/v0/resources` | List, filter by `application_id`, `kind`, `environment` |
| `GET` | `/api/v0/resources/{id}` | Get by ID |
| `PATCH` | `/api/v0/resources/{id}` | Update mutable fields |
| `GET` | `/api/v0/resources/{id}/attributes` | List attributes |
| `POST` | `/api/v0/resources/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/resources/{id}/attributes/{key}` | Remove attribute |

## CLI

| Command | Description |
|---|---|
| `al inventory resources list` | List all resources |
| `al inventory resources list --application-id <id>` | Filter by application |
| `al inventory resources list --kind <kind>` | Filter by resource type |
| `al inventory resources get <id>` | Get by ID |
| `al inventory resources create --application-id <id> --external-id <id> --kind <kind>` | Create |
| `al inventory resources update <id> --privilege-level <level>` | Update |
| `al inventory resources attributes <id>` | List attributes |
| `al inventory resources add-attribute <id> <key> <value>` | Add attribute |
| `al inventory resources remove-attribute <id> <key>` | Remove attribute |
