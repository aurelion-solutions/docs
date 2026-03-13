# Employee

The canonical internal human identity. Policies, access facts, and reconciliation rules all operate on Employees. Backed by a Person.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `person_id` | UUID | FK to Person |
| `is_locked` | boolean | Blocks access when true; checked by PDP |
| `description` | string | Display label |

Extensible via key-value attributes. Common attribute keys used by the PDP: `employment_status`, `department`, `mfa_enrolled`, `risk_score`.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/employees` | Create an employee |
| `GET` | `/api/v0/employees` | List all employees |
| `GET` | `/api/v0/employees/{id}` | Get by ID |
| `PATCH` | `/api/v0/employees/{id}` | Update (`is_locked`, `description`) |
| `GET` | `/api/v0/employees/{id}/attributes` | List attributes |
| `POST` | `/api/v0/employees/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/employees/{id}/attributes/{key}` | Remove attribute |

## CLI

| Command | Description |
|---|---|
| `al employees list` | List all employees |
| `al employees get <id>` | Get by ID |
| `al employees attributes <id>` | List attributes |

Create, update, and attribute management are API-only.
