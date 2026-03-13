# NHI (Non-Human Identity)

Service accounts, bots, CI pipelines, and daemons. NHIs participate in policies and audit on equal footing with human identities.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `external_id` | string | Identifier in the source system |
| `name` | string | Display name |
| `kind` | string | Type of NHI (e.g. `service_account`, `bot`, `pipeline`) |
| `is_locked` | boolean | Blocks access when true |
| `owner_employee_id` | UUID | Optional responsible human owner |
| `application_id` | UUID | Optional originating application |

Extensible via key-value attributes.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/nhis` | Create an NHI |
| `GET` | `/api/v0/nhis` | List all NHIs |
| `GET` | `/api/v0/nhis/{id}` | Get by ID |
| `GET` | `/api/v0/nhis/{id}/attributes` | List attributes |
| `POST` | `/api/v0/nhis/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/nhis/{id}/attributes/{key}` | Remove attribute |

## CLI

| Command | Description |
|---|---|
| `al nhi list` | List all NHIs |
| `al nhi get <id>` | Get by ID |
| `al nhi create --external-id <id> --name <name> --kind <kind>` | Create |
| `al nhi attributes <id>` | List attributes |
| `al nhi add-attribute <id> --key <k> --value <v>` | Add attribute |
| `al nhi remove-attribute <id> <key>` | Remove attribute |
