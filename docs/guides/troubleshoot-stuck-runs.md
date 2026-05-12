# How to troubleshoot stuck pipeline runs

Use this guide when a pipeline run has been in a non-terminal state longer than
expected and you need to diagnose why it has not progressed.

## What you need

- Access to the platform API (read-only is sufficient for diagnosis).
- The `aurelion-cli` (`al`) installed, or `curl` + `jq`.
- Read access to the event bus or the log sink (useful for liveness checks, but
  not strictly required).

## Symptom → likely cause

| Observed state | Likely cause |
|---|---|
| `status=pending` for more than a few seconds | No executor is consuming the queue.  Check executor liveness. |
| `status=running` with a stale `last_heartbeat_at` | The worker crashed.  The reclaim sweep will recover the run automatically within ~10 s. |
| `status=awaiting_event` past the expected wake-up time | The matching event was never published, or the `match` expression does not satisfy the payload. |
| `status=cancelling` for more than a few seconds | The current step is in a tight CPU loop with no `await` points; executor cannot honour the cancel signal.  Rare — capture logs and force-fail. |
| `status=failed` with `error=event_timeout` | The waiter expired.  This is not a stuck run — it is a correctly failed run.  Retry or fix the upstream signal. |

## Inspect the run

Fetch the run record and focus on the diagnostic fields:

```bash
# REST
curl -s http://localhost:8000/api/v0/pipeline-runs/00000000-0000-0000-0000-000000000001 | jq '{status, worker_id, current_step, last_heartbeat_at, error}'

# CLI
al pipelines runs get 00000000-0000-0000-0000-000000000001 --format json
```

Fields that matter for diagnosis:

- `status` — where the run is in its lifecycle.
- `last_heartbeat_at` — the last time the executor wrote a heartbeat.  If this
  is more than `EXECUTOR_HEARTBEAT_SECONDS` in the past, the worker may be
  gone.
- `worker_id` — which executor slot owns the run.  `null` on `awaiting_event`
  is normal.
- `current_step` — the step the run was last seen executing or waiting at.
- `error` — populated on failure; `event_timeout` points to the waiter guide.

Field definitions are in
[`../reference/pipeline-runs-api.md#pipelinerun-fields`](../reference/pipeline-runs-api.md#pipelinerun-fields).

## Inspect the steps

List all step attempts for the run:

```bash
curl -s http://localhost:8000/api/v0/pipeline-runs/00000000-0000-0000-0000-000000000001/steps \
  | jq '[.[] | {name, status, attempt, error}]'
```

Useful observations:

- A step with `status=aborted` and `attempt > 1` is a forensic marker from a
  reclaim event.  The prior attempt was interrupted; a new attempt was started.
  This is the reclaim mechanism working correctly — not a problem to fix.
- A step with `status=running` but its parent run's heartbeat is stale
  confirms the worker-crash scenario.
- A step with `status=awaiting_event` alongside the run itself confirms a
  waiter is parked.

## Check executor liveness

The executor publishes `executor.process.heartbeat` events to the bus every
`EXECUTOR_HEARTBEAT_SECONDS` seconds.  If no such events appear for more than
two heartbeat intervals, the executor process is down.

Check the liveness event stream in your log sink or MQ monitor.  The event
schema is documented in
[`../reference/pipeline-events.md#executor-liveness`](../reference/pipeline-events.md#executor-liveness).

The `EXECUTOR_HEARTBEAT_SECONDS` setting and its defaults are in
[`../reference/runtime-settings.md`](../reference/runtime-settings.md).

For a conceptual overview of how the two heartbeat layers (DB row vs MQ event)
interact, see
[`../concepts/heartbeat-architecture.md`](../concepts/heartbeat-architecture.md).

## Check beat and matcher

The API process (not the executor) owns the beat sweep and the event matcher.

- **Beat** fires every tick and transitions timed-out waiters to
  `failed_timeout`, reclaims stale runs, and fires schedule triggers.
- **Matcher** listens on the bus and resolves `awaiting_event` runs when a
  matching event arrives.

If schedule-triggered runs are not starting despite active schedules, or if
`awaiting_event` runs are not waking up despite events being published, the API
process itself may be stuck or the advisory lock may be contended (another API
replica holds it).

Standard recovery: restart the stuck API replica.  The next replica to start
acquires the advisory lock and resumes normal beat and matcher operation.
For lock key details, see
[`../concepts/heartbeat-architecture.md#beat-and-matcher-locks`](../concepts/heartbeat-architecture.md#beat-and-matcher-locks).

## Decide the next action

Work through the following decision tree:

**Worker crash, stale heartbeat** — wait 10 s and re-inspect.  The reclaim
sweep will mark the prior attempt `aborted`, insert a new attempt, and the run
will re-enter `pending`.  If it stays `running` after 30 s, the executor is
down — restart it.  Pending and reclaimed runs are picked up automatically on
executor restart.

**`awaiting_event`, past expected wake-up** — cancel the run, diagnose the
matcher expression and the upstream payload (see
[`./wait-for-external-event.md#common-pitfalls`](./wait-for-external-event.md#common-pitfalls)),
fix the YAML or the upstream publisher, then retry (see
[`./retry-failed-run.md`](./retry-failed-run.md)).

**`pending` with no executor** — confirm the executor process is running and
consuming from the queue.  Restart if down.

**`cancelling` stuck** — the step in `current_step` is not yielding.  Capture
the executor logs (search for `worker_id`), then cancel the run via
`POST /api/v0/pipeline-runs/{run_id}/cancel` a second time if the transition
still has not completed after the next heartbeat.  File an issue with the log
capture.

**`failed` with `error=event_timeout`** — not stuck; properly failed.  Retry
once the upstream signal system is confirmed healthy.

**Genuine bug** — cancel the run, capture executor and API logs, file an issue.
Do not retry until the root cause is understood.

## See also

- [`../concepts/heartbeat-architecture.md`](../concepts/heartbeat-architecture.md) — two-heartbeat model, reclaim mechanics
- [`../concepts/idempotency-and-reclaim.md`](../concepts/idempotency-and-reclaim.md) — why reclaim is safe and how it interacts with idempotency
- [`../reference/pipeline-events.md`](../reference/pipeline-events.md) — run-level, step-level, and executor liveness events
- [`../reference/runtime-settings.md`](../reference/runtime-settings.md) — `EXECUTOR_HEARTBEAT_SECONDS` and related tunables
- [`../cli/pipelines.md`](../cli/pipelines.md) — full CLI command reference for run inspection
