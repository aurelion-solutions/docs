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

## Events

| Event | When | Payload |
|---|---|---|
| `connector.result.received` | Successful ingest of an `inline` or `lake_ref` result | `result_id`, `application_id`, `task_id`, `now` |

`artifacts_bulk` results do not emit this event — they emit their own batch event (see `inventory.access_artifacts.batch_ingested` in `reference/access-artifacts.md`).

### Payload fields

| Field | Type | Description |
|---|---|---|
| `result_id` | UUID string | Identifier of the staged `staging_connector_results` row |
| `application_id` | UUID string | Application the result belongs to |
| `task_id` | UUID string | Originating connector task |
| `now` | ISO-8601 datetime (UTC) | Server-side ingest timestamp. Consumed by the `application_sync` pipeline as the projection cut-off (`effective_access.project_application` `now` arg). Always present since Phase 18 Step 21. |

Consumer contract: any downstream subscriber that expects to drive a pipeline run via `args_from_payload` (see [Pipeline YAML](pipeline-yaml.md)) can rely on `now` being present. The field is stamped at emit time, not at task completion — it is the moment the staging row was written, not the moment the connector finished work.

See [Events and Logs](../concepts/events.md) for envelope and bus semantics.

## No CLI equivalent

Connector results are posted by connector processes, not interactively.
