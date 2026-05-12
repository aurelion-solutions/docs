# How to cancel a pipeline run

Use this guide when you have a pipeline run in flight and need to stop it
immediately — for example, a misconfigured pipeline that would write bad data,
or an approval run that was superseded by an out-of-band decision.

## What you need

- A `pipeline_run_id` (UUID).  You can get it from the runs list (`GET
  /api/v0/pipeline-runs`) or from the event that created the run.
- Knowledge of the run's current status.  Cancellation behaves differently
  depending on whether the run is `pending`, `running`, `awaiting_event`,
  already `cancelling`, or in a terminal state.
- CLI installed (for the CLI path) or HTTP access to the platform API (for the
  REST path).

## Pick your method

Use the CLI for ad-hoc intervention during an incident.  Use the REST endpoint
when driving cancellation from an automation script, a CI gate, or a
downstream system.

- CLI reference: [`../cli/pipelines.md#al-pipelines-runs-cancel-run_id`](../cli/pipelines.md#al-pipelines-runs-cancel-run_id)
- REST reference: [`../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel`](../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel)

## Cancel via CLI

```bash
al pipelines runs cancel 00000000-0000-0000-0000-000000000001
```

Expected output on success:

```
Run 00000000-0000-0000-0000-000000000001 — cancellation requested.
Status: cancelling
```

The run transitions to `cancelling` immediately.  The executor picks up the
signal on its next heartbeat cycle (within seconds) and sets the run to
`cancelled`.  See the full flag reference in
[`../cli/pipelines.md#al-pipelines-runs-cancel-run_id`](../cli/pipelines.md#al-pipelines-runs-cancel-run_id).

## Cancel via REST

```bash
curl -s -X POST \
  -H "Content-Type: application/json" \
  http://localhost:8000/api/v0/pipeline-runs/00000000-0000-0000-0000-000000000001/cancel \
  | jq .
```

A `200 OK` response looks like:

```json
{
  "run_id": "00000000-0000-0000-0000-000000000001",
  "status": "cancelling",
  "pipeline_name": "application_sync",
  "pipeline_version": "1.0.0",
  "created_at": "2026-05-01T10:00:00Z",
  "updated_at": "2026-05-01T10:01:30Z"
}
```

The full response schema is in
[`../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel`](../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel).

## What cancel does per status

| Current status | Outcome |
|---|---|
| `pending` | Run never starts; transitions directly to `cancelled`. |
| `running` | Executor receives the cancellation signal on next heartbeat; step is aborted, run moves to `cancelling` → `cancelled`. |
| `awaiting_event` | Waiter is released; run moves to `cancelling` → `cancelled` without waiting for the external event. |
| `cancelling` | `409 Conflict` — cancellation already in progress.  No action needed; wait for `cancelled`. |
| Terminal (`cancelled`, `failed`, `completed`, …) | `409 Conflict` — run has already ended, cannot be cancelled again. |

The heartbeat mechanics behind the `running → cancelling → cancelled`
transition are explained in
[`../concepts/heartbeat-architecture.md`](../concepts/heartbeat-architecture.md).

## How to verify

Check the run status directly:

```bash
# CLI
al pipelines runs get 00000000-0000-0000-0000-000000000001

# REST
curl -s http://localhost:8000/api/v0/pipeline-runs/00000000-0000-0000-0000-000000000001 | jq .status
```

When the executor has finished the cancellation, the status field is
`cancelled`.  Confirm the domain event was emitted:

```bash
# REST — list recent events scoped to this run (bus / log sink query)
curl -s "http://localhost:8000/api/v0/pipeline-runs/00000000-0000-0000-0000-000000000001/steps" | jq '[.[] | {name, status, attempt}]'
```

Look for a `pipeline.run.cancelled` event in your log sink or MQ monitor.
Run-level events are described in
[`../reference/pipeline-events.md#run-level-events`](../reference/pipeline-events.md#run-level-events).

## Common failures

- **`404 Not Found`** — the `run_id` does not exist.  Double-check the UUID
  (copy-paste errors are common with synthetic IDs).
- **`409 Conflict`** — the run is already in a terminal state or already
  `cancelling`.  Inspect the current status first with `GET
  /api/v0/pipeline-runs/{run_id}`.  Full contract in
  [`../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel`](../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel).
- **`422 Unprocessable Entity`** — the `run_id` is not a valid UUID.  Verify
  the path parameter format.

## See also

- [`../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel`](../reference/pipeline-runs-api.md#post-pipeline-runsrun_idcancel) — full cancel endpoint contract
- [`../reference/pipeline-events.md#run-level-events`](../reference/pipeline-events.md#run-level-events) — `pipeline.run.cancelled` event
- [`../concepts/heartbeat-architecture.md`](../concepts/heartbeat-architecture.md) — how cancel interacts with heartbeat and reclaim
- [`../concepts/pipeline-orchestrator.md`](../concepts/pipeline-orchestrator.md) — pipeline run lifecycle overview
