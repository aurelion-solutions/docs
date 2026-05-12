# Pipeline Events

Event-type catalogue for routing keys emitted by the pipeline orchestrator.

Source of truth: event-builder functions in
`aurelion-kernel/src/platform/orchestrator/service.py` (grep `_run_*_event`,
`_step_*_event`) and
`aurelion-kernel/src/platform/orchestrator/liveness.py` for the executor heartbeat.

## Bus and envelope

All events are published to the `aurelion.events` topic exchange. Each event is
wrapped in an `EventEnvelope` with a 3-segment routing key invariant
(`<domain>.<entity>.<verb>`, e.g. `pipeline.run.created`).

**Advisory-lock keys** — the orchestrator uses two reserved Postgres advisory
lock keys that must not be reused by other components:

- `_BEAT_LOCK_KEY` (`beat.py`, per-tick) — held by the schedule beat process
  for the duration of each 10 s tick window; only one replica fires per tick.
- `_MATCHER_LOCK_KEY` (`matcher.py`, session-level) — held for the lifetime of
  the matcher consumer session; only one replica consumes MQ messages at a time.

Both constants are defined in their respective modules (see ARCH_CONTEXT lines
393–396).

## Run-level events

Emitted by `service.py`. Every payload includes `run_id` (UUID string).

| Routing key | Additional payload fields | When |
|---|---|---|
| `pipeline.run.created` | `pipeline_name`, `pipeline_version` | A new `PipelineRun` row is inserted |
| `pipeline.run.started` | — | The runner picks up the run and begins execution |
| `pipeline.run.completed` | — | All steps completed successfully |
| `pipeline.run.failed` | `error` (string) | A step failed and `on_error=fail`; or an unhandled error terminated the run |
| `pipeline.run.heartbeat_lost` | `previous_worker_id`, `stale_for_seconds` | The reclaim transaction stamps a stale run as heartbeat-lost |
| `pipeline.run.cancelled` | `previous_status` | A run is cancelled (sync via `pending`/`awaiting_event`, or async via `running → cancelling → cancelled`) |

## Step-level events

Emitted by `service.py`. Every payload includes `run_id`, `step_run_id`, and
`step_name`.

| Routing key | Additional payload fields | When |
|---|---|---|
| `pipeline.step.started` | — | The runner begins executing a step attempt |
| `pipeline.step.completed` | `result` (dict \| null) | The step handler returned successfully |
| `pipeline.step.failed` | `error` (string) | The step handler raised an exception |
| `pipeline.step.aborted` | `attempt` (int), `reason` (string) | The reclaim transaction stamps an abandoned prior attempt as aborted |

`pipeline.step.aborted` is a forensic marker only — it does not change the
`PipelineRun` status. The run transitions to `pending` via
`pipeline.run.heartbeat_lost` so a new worker can pick it up.

## Waiter resolution

`wait_for_event` steps park the run as a `PipelineEventWaiter` row until a
matching event arrives or the timeout expires. Matching uses a containment
predicate (`match` JSONB `<@` event payload). For predicate rules and the
nested-list containment caveat see
[Pipeline YAML — Matcher semantics](pipeline-yaml.md#matcher-semantics).

When a waiter is resolved the row is deleted, the step transitions to `completed`
with `result = event.payload`, and the run transitions from `awaiting_event` back
to `pending` so the runner can continue.

## Executor liveness

`platform_executor_node` publishes an `executor.process.heartbeat` event
periodically. Interval is configured via `EXECUTOR_HEARTBEAT_SECONDS` — see
[Runtime Settings — Bootstrap env vars](runtime-settings.md#bootstrap-env-vars-executor-node).

### Event catalogue entry

| Field | Value |
|---|---|
| `event_type` | `executor.process.heartbeat` |
| Exchange | `aurelion.events` (topic) |
| Routing key | `executor.process.heartbeat` |
| Transport | `EventService.emit` (load-bearing, re-raises on failure) |
| Schema version | `1` |

### Payload schema (`ExecutorHeartbeatPayload`)

| Field | Type | Constraints | Description |
|---|---|---|---|
| `worker_id` | string | non-empty | `<hostname>-<pid>-<slot_index>` |
| `slot_index` | int | `>= 0` | Concurrency slot within the process |
| `started_at` | datetime | UTC-aware | When the executor process started |
| `pipelines_loaded` | int | `>= 0` | Number of pipeline definitions loaded at startup |

The first heartbeat is emitted immediately on process start; subsequent
heartbeats fire every `EXECUTOR_HEARTBEAT_SECONDS`. Failed emissions are caught,
logged as WARNING, and the loop continues — the publisher never crashes the
executor process.

No new MQ exchange, queue, or binding is required — the event rides the existing
`aurelion.events` exchange.

## Cross-reference: connector.result.received

The `application_sync` pipeline is MQ-triggered by `connector.result.received`.
See [Connector Results — Payload fields](connector-results.md#payload-fields) for
the full payload contract including the `application_id` and `now` fields
consumed by `args_from_payload`.

## Source of truth

- `aurelion-kernel/src/platform/orchestrator/service.py`
- `aurelion-kernel/src/platform/orchestrator/liveness.py`
- `aurelion-kernel/src/platform/orchestrator/liveness_schemas.py`
