# Artifact Binding

The audit link between a raw AccessArtifact and whatever was produced from it. Answers the question: "where did this access fact / resource / account come from?" Immutable — bindings are created once and never modified.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `artifact_id` | UUID | FK to AccessArtifact |
| `target_type` | string | `access_fact`, `resource`, `account`, or `subject` |
| `target_id` | UUID | FK to the target entity |
| `created_at` | datetime | When the binding was created |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/artifact-bindings` | List, filter by `artifact_id`, `target_type`, `target_id` |
| `GET` | `/api/v0/artifact-bindings/{id}` | Get by ID |

Read-only. Bindings are created by the normalization and reconciliation pipelines.

## CLI

| Command | Description |
|---|---|
| `al inventory artifact-bindings list` | List all bindings |
| `al inventory artifact-bindings list --artifact <id>` | Filter by artifact |
| `al inventory artifact-bindings list --target-type <type>` | Filter by target type |
| `al inventory artifact-bindings list --target-id <id>` | Filter by target entity |
| `al inventory artifact-bindings get <id>` | Get by ID |
