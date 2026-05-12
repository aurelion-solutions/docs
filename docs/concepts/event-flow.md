# Event Flow

The pipeline orchestrator participates in `aurelion.events` in two
distinct roles: as an emitter of state-change events, and as a
consumer that listens for events to fire triggers and resolve
in-flight waiters. This page explains both roles and the reasoning
behind the direct-emit design choice.

For background on the two-bus model, `EventEnvelope`, routing key
format, and correlation ID propagation, see
[Events and Logs](events.md). This page focuses on the
orchestrator's specific use of that infrastructure.

## Two roles on the same bus

Every pipeline state transition — run created, step started, run
completed — produces an event on `aurelion.events`. That is the
emitter role: `platform/orchestrator/service.py` writes the events.

The same bus also carries the external events that drive pipelines
forward. MQ triggers fire when an event matching a routing key and
predicate arrives. `wait_for_event` steps park until a matching event
resolves them. That is the consumer role: `matcher.py` reads from
the exchange to handle both cases.

One bus, one component, two directions of flow.

## As emitter

The single-emitter rule applies: only `platform/orchestrator/service.py`
writes to the `pipeline.*` event families. No other file in the
codebase emits these events. Engine actions executed inside a pipeline
step may emit their own events (under their own namespaces), but they
do not emit `pipeline.*` events.

The routing key invariant for all orchestrator events is three
segments, lowercase snake_case: `pipeline.run.<verb>` or
`pipeline.step.<verb>`. This matches the platform-wide
`<domain>.<entity>.<verb>` pattern documented in ARCH_CONTEXT. The
full catalogue of routing keys and payload fields is in
[Pipeline Events](../reference/pipeline-events.md).

Correlation context is seeded when `claim_pending_run` succeeds and
inherited by every event and log emitted within that run. Every
`pipeline.run.*` and `pipeline.step.*` event for the same run shares
the same `correlation_id`, which allows a consumer or operator to
join all events for a run by that field.

## As consumer — MQ triggers

A pipeline YAML can declare a `trigger_mq` block that binds the
pipeline to a routing key on `aurelion.events`. When an event
arrives, `matcher.py` evaluates the predicate: the `match` block is
satisfied when the JSONB object is contained in the event payload
(`<@`), and the `args_from_payload` map extracts pipeline args from
dotted payload paths.

If the predicate is satisfied and no identical in-flight run exists,
the matcher calls the service to insert a new `PipelineRun` row with
`trigger_source=mq`. The partial-UNIQUE index on `(pipeline_name,
pipeline_version, content_hash)` blocks duplicate runs from re-delivered
events when the args are identical — this is the trigger-level
idempotency guarantee. For the predicate semantics and the nested-list
containment caveat, see
[Pipeline YAML — Matcher semantics](../reference/pipeline-yaml.md#matcher-semantics).

## As consumer — wait_for_event waiters

A `wait_for_event` step parks the run instead of executing engine
work. The executor inserts a `pipeline_event_waiters` row with the
expected routing key, a `match` predicate, and a required `expires_at`
deadline. The `PipelineRun` status transitions to `awaiting_event`,
and `worker_id` is cleared so the reclaim sweep does not consider
the parked run abandoned.

This is distinct from the MQ trigger case: the run already exists and
is waiting for an event to continue. The matcher consumer handles
both cases in the same message loop: incoming events are checked
against both the trigger table and the waiters table.

When a matching event arrives, the matcher resolves the waiter: the
`pipeline_event_waiters` row is deleted, the `StepRun` transitions
to `completed` with `result = event.payload`, and the `PipelineRun`
returns to `pending` so a worker can continue from the next step.
For the full resolution sequence, see
[Pipeline Events — Waiter resolution](../reference/pipeline-events.md#waiter-resolution).

## Why direct emit, not outbox

Orchestrator state-change events are emitted inside the same database
transaction that updates `pipeline_runs` or `step_runs`. The sequence
is: flush state change → emit event → commit (caller's transaction
boundary). If the MQ publish fails after the Postgres commit, the
event is lost — there is no `events_outbox` table to retry from.

This is a deliberate trade-off, not an oversight. An outbox pattern
would require every emit site across the platform to write to an
outbox table and a separate relay to drain it. Adding that only for
the orchestrator would create asymmetry: orchestrator events would
have different delivery semantics than events from every other
service. The consistent platform model is direct emit with a small
acknowledged risk of loss on transport failure.

The trade-off is reversible. Interposing an outbox requires changing
`EventService.emit` to also write to an `events_outbox` row in the
same transaction, then adding a relay. The change is bounded to the
event infrastructure layer and does not require touching each call
site individually. The open decision is tracked in
`aurelion-mas/feedbacks/2026-05-10-event-outbox-todo.md`.

## Correlation

Orchestrator events carry the same `correlation_id` propagation as
the rest of the bus. The correlation context is seeded once per run
when the worker claims it. Every `pipeline.*` event and every log
record emitted while processing that run inherits the same ID without
the service layer threading it explicitly through every call.
For propagation semantics, see [Events and Logs](events.md).

## See also

- [Events and Logs](events.md) — two-bus model, `EventEnvelope`,
  routing key format, correlation ID propagation, single-emitter rule
- [Pipeline Events](../reference/pipeline-events.md) — full event
  catalogue: run-level, step-level, waiter resolution, executor liveness
- [Pipeline YAML](../reference/pipeline-yaml.md) — `trigger_mq` block,
  `args_from_payload`, `wait_for_event` step type
- [Idempotency and Reclaim](idempotency-and-reclaim.md) — trigger-level
  deduplication and at-least-once delivery consequences
