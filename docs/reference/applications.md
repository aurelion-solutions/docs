# Application

The configuration record for a connector-backed integration. Reconciliation, provisioning, and ingest all operate per-application. The `code` field is the stable machine identifier used by the PDP and policy mapping files.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | string | Display name — can be renamed freely |
| `code` | string | Stable machine ID (`^[a-z0-9][a-z0-9_-]{0,63}$`); used by PDP as `target.application` |
| `config` | JSON | Opaque execution config passed to the connector |
| `required_connector_tags` | string[] | Tags a connector instance must have to serve this app |
| `is_active` | boolean | Disables the application when false |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/applications` | List all applications |
| `POST` | `/api/v0/applications` | Create |
| `PATCH` | `/api/v0/applications/{id}` | Update name, code, config, tags, or active flag |
| `DELETE` | `/api/v0/applications/{id}` | Delete |

## CLI

| Command | Description |
|---|---|
| `al app list` | List all applications |
| `al app create --name <name> --code <code>` | Create |
| `al app create --name <name> --code <code> --required-tags '["tag"]'` | Create with connector tags |
| `al app delete --app-id <id>` | Delete |

## Errors

| Code | Condition |
|---|---|
| 409 | `code` already taken by another application |
| 422 | Validation failure (invalid `code` format, missing required fields) |
