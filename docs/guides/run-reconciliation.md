# How to run reconciliation

Reconciliation compares the latest artifact snapshot for an application against the current access facts and persists the per-row delta. Apply (writing to `access_facts`) is a separate concern — pick the run mode that matches your goal.

## Prerequisites

- An application registered in Aurelion — see [Connect an application](connect-application.md)
- At least one ingested artifact batch in the lake for that application
- A connector instance online and resolvable for the application

## Pick a mode

| Goal | Mode | Terminal status |
|---|---|---|
| Stage the diff and review it before applying | `review` (default) | `pending_apply` |
| See what would change without intent to apply | `dry_run` | `dry_run_completed` |
| Apply end-to-end in one request | `auto_apply` | `applied` or `partially_applied` |

## Run via API

```bash
curl -X POST http://localhost:8000/api/v0/reconciliation/runs \
  -H "Content-Type: application/json" \
  -d '{
        "application_id": "550e8400-e29b-41d4-a716-446655440000",
        "mode": "review"
      }'
```

Successful response (truncated):

```json
{
  "id": "9f0e...",
  "status": "pending_apply",
  "created_count": 5,
  "updated_count": 2,
  "revoked_count": 1,
  "unchanged_count": 34,
  "observed_snapshot_id": "...",
  "current_snapshot_id": "..."
}
```

## Run via CLI

```bash
al reconciliation run --application-id <application-uuid>
```

The CLI defaults to `mode=review`. CLI flags for `dry_run` / fetching delta items land in a later phase.

## Inspect the result

Fetch the run record:

```bash
curl http://localhost:8000/api/v0/reconciliation/runs/<run-id>
```

Page through the delta items:

```bash
# First page
curl "http://localhost:8000/api/v0/reconciliation/runs/<run-id>/delta-items?limit=100"

# Filter by status
curl "http://localhost:8000/api/v0/reconciliation/runs/<run-id>/delta-items?status=create"

# Next page — pass next_cursor back unchanged
curl "http://localhost:8000/api/v0/reconciliation/runs/<run-id>/delta-items?cursor=<next_cursor>"
```

When the response's `next_cursor` is `null`, you have read the full list.

## Common failures

**`409 Conflict — Reconciliation already running for this application`** — Another run for the same application is in flight. Wait for it to finish (runs are short and the advisory lock is released on both success and failure paths) and retry. Different applications run in parallel.

**`404 Not Found` on `POST`** — The `application_id` does not exist. Verify the UUID against `GET /api/v0/applications`.

**`422 Unprocessable Entity`** — Bad payload: missing `application_id`, unknown `mode`, malformed cursor, `limit` outside `1..1000`, or unknown `status` filter.

## What happens after a run

The engine emits a sequence of events on `aurelion.events`:

- `reconciliation.run.started` — published as the run begins
- `reconciliation.delta.created` — counts of created/updated/revoked/unchanged items
- `reconciliation.run.completed` — terminal status (`pending_apply` or `dry_run_completed`)
- `reconciliation.run.failed` — only on failure, in place of `delta.created` and `run.completed`

All four events share `run_id` and `correlation_id`. See [Events and Logs](../concepts/events.md#reconciliation-event-ordering) for ordering rules.

When `mode=auto_apply` (or after a manual apply call — see below), `SyncApplyService` additionally emits one `inventory.access_fact.{created,updated,revoked,reactivated}` event per applied delta item. Each carries `delta_item_id`, `snapshot_id`, and `reconciliation_run_id`.

For full request/response shapes, see the [Reconciliation reference](../reference/reconciliation.md).

## Apply after a review

If you ran with `mode=review`, the run is left in `pending_apply` with delta items that you can mark `approved`, then trigger apply explicitly:

```bash
curl -X POST http://localhost:8000/api/v0/reconciliation/runs/<run-id>/apply \
  -H "Content-Type: application/json" \
  -d '{"mode": "manual_apply"}'
```

Apply only the items you select:

```bash
curl -X POST http://localhost:8000/api/v0/reconciliation/runs/<run-id>/apply \
  -H "Content-Type: application/json" \
  -d '{"mode": "selected_items", "item_ids": ["<delta-item-uuid>", "..."]}'
```

Dry-run the apply preflight without writing to the lake:

```bash
curl -X POST http://localhost:8000/api/v0/reconciliation/runs/<run-id>/apply \
  -H "Content-Type: application/json" \
  -d '{"mode": "dry_run"}'
```

Common apply failures:

- `404 Not Found` — the `run_id` does not exist.
- `409 Conflict` — an apply for this run is already running or has already completed. Apply is idempotent at the run level: a successful apply is not re-runnable.
- `422 Unprocessable Entity` — `selected_items` was passed without `item_ids`, or one of the listed items is not in `approved`.

For the full apply contract, see [Reconciliation reference / Apply runs](../reference/reconciliation.md#apply-runs).

## Automation

Reconciliation does not run on a schedule. Trigger it from your orchestration layer (cron, workflow engine, connector post-push hook) after each artifact ingest — and propagate `X-Correlation-ID` so the run's events stay joinable with whatever upstream action triggered it.
