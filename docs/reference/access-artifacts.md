# Access Artifact

Append-only raw access evidence from connectors. Every piece of access data that enters Aurelion starts as an artifact. Artifacts are never modified or deleted — they are the permanent record of what connectors reported.

The `artifact_type` field determines which reconciliation handler processes the artifact.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `application_id` | UUID | FK to Application |
| `artifact_type` | string | Handler dispatch key (e.g. `role`, `acl_entry`, `db_grant`) |
| `external_id` | string | Identifier in the source system |
| `payload` | JSON | Raw data in source vocabulary |
| `effect` | string | `allow` or `deny` |
| `is_active` | boolean | Whether the artifact is currently active |
| `observed_at` | datetime | When the connector observed this access |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/access-artifacts` | List, filter by `application_id`, `artifact_type` |
| `GET` | `/api/v0/access-artifacts/{id}` | Get by ID |

Read-only. Artifacts are created by the normalization pipeline, not directly.

## CLI

| Command | Description |
|---|---|
| `al inventory artifacts list` | List all artifacts |
| `al inventory artifacts list --application-id <id>` | Filter by application |
| `al inventory artifacts list --artifact-type <type>` | Filter by type |
| `al inventory artifacts get <id>` | Get by ID |
