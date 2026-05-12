# How to retry a failed pipeline run

Use this guide when a pipeline run has entered a terminal failure state and you
want to start a fresh attempt with the same pipeline definition and arguments.

## What you need

- A `pipeline_run_id` whose `status` is one of: `failed`, `failed_timeout`, or
  `cancelled`.
- Confirmation that the root cause is resolved (see the section below on when
  *not* to retry).
- CLI installed or HTTP access to the platform API.

The retry endpoint **does not accept** runs in `cancelling` or any active
status (`pending`, `running`, `awaiting_event`).  Check the current status
first with `GET /api/v0/pipeline-runs/{run_id}` before retrying.

## When to retry vs when not to

**Retry makes sense** when the failure was transient:

- A network blip or MQ flap that timed out a step.
- A downstream service returned a temporary `5xx` during an engine call.
- The run hit `failed_timeout` because the external event arrived after the
  waiter expired (fix the `expires_at` in the YAML, then retry).

**Do not retry blindly** when the failure was structural:

- Bad `args` that fail schema validation — fix the pipeline call site first.
- A broken pipeline definition (YAML syntax error, missing action) — fix the
  definition and re-deploy.
- A contract violation in an engine action — the action will fail again with
  identical arguments.
- An `event_timeout` failure where the upstream signal system is permanently
  unavailable — retry will just time out again.

**Reclaim is automatic and is not retry.**  If a worker crashed mid-run, the
beat sweep reclaims the run within seconds and resumes it from `current_step`
without any operator action.  See
[`../concepts/idempotency-and-reclaim.md#reclaim-briefly`](../concepts/idempotency-and-reclaim.md#reclaim-briefly)
for the distinction.

## Retry via CLI

```bash
al pipelines runs retry 00000000-0000-0000-0000-000000000001
```

Expected output on success:

```
Retry created.
New run ID: 00000000-0000-0000-0000-000000000002
Retry of:   00000000-0000-0000-0000-000000000001
Status:     pending
```

Full flag reference:
[`../cli/pipelines.md#al-pipelines-runs-retry-run_id`](../cli/pipelines.md#al-pipelines-runs-retry-run_id).

## Retry via REST

```bash
curl -s -X POST \
  -H "Content-Type: application/json" \
  http://localhost:8000/api/v0/pipeline-runs/00000000-0000-0000-0000-000000000001/retry \
  | jq .
```

A `201 Created` response:

```json
{
  "run_id": "00000000-0000-0000-0000-000000000002",
  "retry_of_run_id": "00000000-0000-0000-0000-000000000001",
  "status": "pending",
  "pipeline_name": "application_sync",
  "pipeline_version": "1.0.0",
  "created_at": "2026-05-01T10:05:00Z"
}
```

Full endpoint contract:
[`../reference/pipeline-runs-api.md#post-pipeline-runsrun_idretry`](../reference/pipeline-runs-api.md#post-pipeline-runsrun_idretry).

## What gets carried over

The new run inherits:

- Same `pipeline_name` and `pipeline_version`.
- Same `args` (and therefore same `content_hash`).
- `retry_of_run_id` is set to the original run's ID, which exempts the new
  row from the in-flight UNIQUE constraint (`pipeline_name`,
  `idempotency_key`) that normally blocks duplicate active runs.

The new run **starts from step 1**, not from the failed step.  This is
intentional: engine actions must be idempotent, so a clean re-run from the
top is safe regardless of how far the original run progressed.  See
[`../concepts/idempotency-and-reclaim.md#the-contract`](../concepts/idempotency-and-reclaim.md#the-contract)
for why idempotency is a hard requirement for all registered actions.

## Common failures

- **`404 Not Found`** — the source `run_id` does not exist.
- **`409 Conflict — RunNotRetryableError`** — the run's current status is
  `cancelling` or is not one of the terminal-failure statuses.  Check the
  status and reason in the response body.  Full contract in
  [`../reference/pipeline-runs-api.md#post-pipeline-runsrun_idretry`](../reference/pipeline-runs-api.md#post-pipeline-runsrun_idretry).
- **`422 Unprocessable Entity`** — malformed UUID in the path.

## See also

- [`../reference/pipeline-runs-api.md#post-pipeline-runsrun_idretry`](../reference/pipeline-runs-api.md#post-pipeline-runsrun_idretry) — full retry endpoint contract
- [`../reference/pipeline-runs-api.md#pipelinerun-fields`](../reference/pipeline-runs-api.md#pipelinerun-fields) — field descriptions including `retry_of_run_id`
- [`../concepts/idempotency-and-reclaim.md`](../concepts/idempotency-and-reclaim.md) — idempotency contract, reclaim mechanics, retry vs reclaim distinction
