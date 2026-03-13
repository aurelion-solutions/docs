# Person

The reusable human profile root. Every Employee is backed by a Person. A Person can exist without an Employee (e.g. a contractor not yet in the system as a canonical identity).

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `external_id` | string | Identifier from the source system |
| `description` | string | Display label |

Extensible via key-value attributes.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/persons` | Create a person |
| `GET` | `/api/v0/persons` | List all persons |
| `GET` | `/api/v0/persons/{id}` | Get by ID |
| `GET` | `/api/v0/persons/{id}/attributes` | List attributes |
| `POST` | `/api/v0/persons/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/persons/{id}/attributes/{key}` | Remove attribute |

## CLI

| Command | Description |
|---|---|
| `al persons list` | List all persons |
| `al persons get <id>` | Get by ID |
| `al persons attributes <id>` | List attributes |

Create, update, and delete are API-only.
