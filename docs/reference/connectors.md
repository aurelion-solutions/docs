# Connector Instance

A registered connector process. Instances self-register with the platform on startup via heartbeat. At reconciliation time the platform picks an instance whose tags satisfy the application's `required_connector_tags`.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Row ID in the registry |
| `instance_id` | string | Stable ID used as RabbitMQ routing key (e.g. `runtime-a`) |
| `tags` | string[] | Tags reported by the instance |
| `is_online` | boolean | Whether the instance is considered online |
| `last_seen_at` | datetime | Last heartbeat time |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/connector-instances` | List all instances |
| `GET` | `/api/v0/connector-instances/{instance_id}` | Get by `instance_id` (not UUID) |

Registration and heartbeat are handled by the connector process itself, not via this API.

## CLI

| Command | Description |
|---|---|
| `al app connectors list` | List all instances |
| `al app connectors list --json` | List as raw JSON |
| `al app connectors get <instance_id>` | Get by instance ID |
