# Employee Record

A source-side human record from an external system (HR, Active Directory, SCIM). Multiple EmployeeRecords from different Applications are composed into a single canonical Employee by the resolver.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `external_id` | string | Identifier in the source system |
| `application_id` | UUID | FK to the source Application (connector) |
| `description` | string | Display label |

Extensible via key-value attributes. Attribute values are used by the composition resolver to match records across sources.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/employee-records` | Create a record |
| `GET` | `/api/v0/employee-records` | List all records |
| `GET` | `/api/v0/employee-records/{id}` | Get by ID |
| `GET` | `/api/v0/employee-records/{id}/attributes` | List attributes |
| `POST` | `/api/v0/employee-records/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/employee-records/{id}/attributes/{key}` | Remove attribute |

## CLI

| Command | Description |
|---|---|
| `al employee-records list` | List all records |
| `al employee-records get <id>` | Get by ID |
| `al employee-records attributes <id>` | List attributes |

Create and attribute management are API-only.
