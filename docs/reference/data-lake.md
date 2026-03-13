# Data Lake

Batch-oriented storage for connector and staging data. Connectors write large result sets here instead of inline; the `lake_ref` result type in connector results references a batch by key.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `storage_provider` | string | Backend (e.g. `file`) |
| `dataset_type` | string | Type of records (e.g. `accounts`, `resources`) |
| `storage_key` | string | Key used to retrieve the payload from the provider |
| `row_count` | int | Number of records in the batch |
| `application_id` | UUID | Optional owning application |
| `task_id` | UUID | Optional originating task |

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/datalake/batches` | Create a batch (write records to the lake) |
| `GET` | `/api/v0/datalake/batches/{id}` | Get batch metadata |
| `GET` | `/api/v0/datalake/batches/{id}/data` | Get batch payload (records) |
| `DELETE` | `/api/v0/datalake/batches/{id}` | Delete batch (metadata + payload) |

## CLI

| Command | Description |
|---|---|
| `al datalake batches create --storage-provider <p> --dataset-type <t> --records <json>` | Create a batch |
| `al datalake batches get <id>` | Get batch metadata |
| `al datalake batches data <id>` | Get batch records |
| `al datalake batches delete <id>` | Delete batch |
