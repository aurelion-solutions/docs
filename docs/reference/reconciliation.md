# Reconciliation

Triggers an artifact-first reconciliation run for one application. Loads active artifacts, dispatches to handlers, applies set-diff against current access facts, emits `reconciliation.run.completed`.

For how the engine works, see [Reconciliation concept](../concepts/reconciliation.md).  
For a step-by-step walkthrough, see [Run reconciliation guide](../guides/run-reconciliation.md).

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/reconciliation/runs` | Trigger a run |

### Request body

```json
{ "application_id": "<uuid>" }
```

### Response

```json
{
  "application_id": "...",
  "started_at": "...",
  "finished_at": "...",
  "artifacts_ingested": 42,
  "facts_created": 5,
  "facts_updated": 2,
  "facts_revoked": 1,
  "artifacts_unhandled": 0,
  "facts_errored": 0
}
```

| Code | Condition |
|---|---|
| 404 | Application not found |
| 422 | Missing or invalid `application_id` |

## CLI

```bash
al reconciliation run --application-id <uuid>
```

Exit code 0 = run completed. Exit code 1 = application not found or HTTP error. Per-artifact errors inside the run do not cause a non-zero exit.
