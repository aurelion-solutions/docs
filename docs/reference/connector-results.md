# Connector Results

The ingest endpoint where connectors post operation outcomes. Writes one row to `staging_connector_results`. No correlation, no domain writes — ingest only. Downstream processing (normalization, reconciliation) happens separately.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/connector-results` | Ingest a connector result |

### Request body

Two result types:

**`inline`** — result data in the request body:
```json
{
  "task_id": "<uuid>",
  "application_id": "<uuid>",
  "operation": "account.create",
  "status": "succeeded",
  "result_type": "inline",
  "result_id": "<uuid>",
  "payload": { "account_id": "ext-123" }
}
```

**`lake_ref`** — result data stored in the Data Lake, only reference stored here:
```json
{
  "task_id": "<uuid>",
  "application_id": "<uuid>",
  "operation": "reconcile",
  "status": "completed",
  "result_type": "lake_ref",
  "result_id": "<uuid>",
  "location": {
    "provider": "file",
    "storage_key": "accounts/batch-1"
  }
}
```

### Response

**200 OK**:
```json
{
  "task_id": "...",
  "result_id": "...",
  "operation": "account.create",
  "status": "succeeded"
}
```

| Code | Condition |
|---|---|
| 404 | Application not found |
| 422 | Invalid UUID, wrong `result_type`, missing `payload` or `location` |

## No CLI equivalent

Connector results are posted by connector processes, not interactively.
