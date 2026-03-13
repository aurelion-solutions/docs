# Initiative

Records *why* an AccessFact exists — the business justification behind a grant. An initiative is always linked to an AccessFact and carries a type, an origin string, and an optional validity window.

Initiatives have no delete endpoint by design. To remove access, revoke the AccessFact.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `access_fact_id` | UUID | FK to AccessFact |
| `type` | enum | `birthright`, `requested`, `delegated`, `inherited`, `grace`, `self_registered`, `invited`, `trial`, `subscription` |
| `origin` | string | Free-form justification (ticket ID, approver, system name) |
| `valid_from` | datetime | Start of validity window |
| `valid_until` | datetime | End of validity window (null = open-ended) |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/initiatives` | List, filter by `access_fact_id`, `type` |
| `GET` | `/api/v0/initiatives/{id}` | Get by ID |
| `POST` | `/api/v0/initiatives` | Create |
| `PATCH` | `/api/v0/initiatives/{id}` | Update `origin`, `valid_from`, `valid_until` |

## CLI

| Command | Description |
|---|---|
| `al inventory initiatives list` | List all initiatives |
| `al inventory initiatives list --access-fact <id>` | Filter by access fact |
| `al inventory initiatives list --type <type>` | Filter by type |
| `al inventory initiatives get <id>` | Get by ID |
| `al inventory initiatives create --access-fact <id> --type <type> --origin <text>` | Create |
| `al inventory initiatives update <id> --origin <text>` | Update origin |
| `al inventory initiatives update <id> --valid-until <iso>` | Set expiry |
