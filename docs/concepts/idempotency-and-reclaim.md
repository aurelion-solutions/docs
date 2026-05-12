# Idempotency and Reclaim

The pipeline orchestrator guarantees at-least-once execution of every
step. That guarantee is only safe if the work being done can be
repeated without producing bad outcomes. This page explains the
idempotency contract every engine action must satisfy, the three
implementation patterns used in the codebase, and the separate
concern of trigger-level deduplication.

## The problem

Distributed systems cannot offer exactly-once delivery. A worker
claims a run, executes a step, and then — before it can record
success — the process crashes, the network drops, or the database
transaction rolls back. From the orchestrator's perspective the step
never finished. It will be retried.

Three concrete sources of repeat execution in this codebase:

- **Reclaim sweeps.** When a worker's DB heartbeat goes stale, the
  reclaim sweep marks the abandoned step `aborted`, inserts a new
  attempt, and returns the run to `pending` for any available worker.
  The new attempt begins from the same step — with the same args.
- **Network blips.** A step action may complete its external work
  (write to Iceberg, call a connector) but fail before committing the
  Postgres status update. The runner rolls back, and the next attempt
  re-runs the same action.
- **Operator retries.** The `POST /api/v0/pipeline-runs/{run_id}/retry`
  endpoint creates a fresh run with the same args. Engine actions
  called by the retry must be safe to call again.

## The contract

`idempotent=True` is mandatory for all engine actions in Phase 18. The
rule is stated in ARCH_CONTEXT and enforced at registration time via
the `@register_action` decorator — see
[Engine Action Registry — The decorator](../reference/engine-action-registry.md#the-decorator)
for the parameter reference.

The contract is precise: given the same `(pipeline_run_id,
step_run_id)` and the same args, re-executing the action produces
**the same observable end state** regardless of how many times it runs.
Side effects that have already occurred must not be duplicated. Side
effects that have not yet occurred must happen exactly once.

## How idempotence is achieved in practice

Three patterns appear in the codebase. Each handles a different kind
of side effect.

**Lake-level dedup.** Actions that write to the Iceberg data lake
first scan for already-written rows before writing. The reconciliation
`inventory_sync` action, for example, performs a DuckDB batch scan against
`normalized.access_facts` to find items whose `reconciliation_delta_item_id`
is already present. Items found in the lake are marked `applied` in
Postgres without a redundant write; the Iceberg writer only touches
items not yet present. A crash after the Iceberg commit but before the
Postgres status update is therefore safe: the next attempt sees the
row in the lake and skips the write.

**Status-guarded UPDATE.** Every status-changing UPDATE on orchestrator
tables (`pipeline_runs`, `step_runs`) includes a WHERE clause that
guards on the expected source status. If the row has already moved
forward — because a concurrent worker or a previous attempt reached
the same state — the UPDATE affects zero rows. The service layer
treats zero rows affected as a signal to refresh and branch (detecting
cancel-vs-complete races), never as a silent retry. This invariant is
stated in ARCH_CONTEXT and applies to all orchestrator state mutations.

**Trigger-level dedup.** A partial UNIQUE index on `(pipeline_name,
pipeline_version, content_hash)` prevents a second in-flight run from
being inserted when identical args are already running. The `content_hash`
is `sha256(canonical_json(args))`. When the index fires, the API returns
the existing run rather than creating a duplicate. See
[Pipeline Runs API — POST /pipeline-runs](../reference/pipeline-runs-api.md)
for the 200 vs 201 response semantics.

## Reclaim, briefly

When a worker's DB heartbeat (`pipeline_runs.last_heartbeat_at`) goes
silent for more than 10 seconds, a reclaim sweep running on another
worker detects the stale row. In a single transaction, the sweep marks
the abandoned `StepRun` as `aborted` (a forensic marker) and inserts
a new attempt resuming from `current_step`. The run returns to
`pending` so any available worker can pick it up.

The previous attempt's `StepRun` is preserved as audit evidence — it
records the worker that held the run, the step it was executing, and
when the heartbeat was last seen. The new attempt starts fresh, but
the engine action it calls must be safe to call again for the same
step args. That is exactly what the idempotency contract provides.

For the mechanics of how reclaim detects stale rows and what the two
heartbeat layers mean for that detection, see
[Heartbeat Architecture](heartbeat-architecture.md).

## Why this matters

Without the idempotency contract, reclaim would be unsafe. A
crash-and-resume cycle would risk:

- Duplicate access facts written to the lake
- Duplicate connector calls (account created twice)
- Duplicate MQ events that mislead downstream projections

The contract is what makes "restart from `current_step`" a correct
algorithm rather than a dangerous one. Reclaim and idempotency are
interdependent: neither is sufficient alone.

## Trigger idempotency, separately

Step-level idempotency and trigger-level idempotency are distinct
concerns that both must be satisfied.

MQ-driven pipeline triggers face at-least-once delivery from
RabbitMQ. The matcher consumer may see the same event more than once.
If the trigger predicate does not deduplicate, a second delivery
produces a second `PipelineRun` row with the same logical meaning.

Every matcher predicate must therefore include a stable idempotency
key — the `event_id`, a `correlation_id`, or a business key that is
stable across re-deliveries. RabbitMQ guarantees at-most-one delivery
per ack only within a single consumer session; re-deliveries after
reconnect, nack, or consumer restart are expected and must be handled.
The requirement is stated in ARCH_CONTEXT (trigger idempotency block).

For the matcher predicate mechanics and the containment-check caveat
for nested lists, see
[Pipeline Events — Waiter resolution](../reference/pipeline-events.md#waiter-resolution).

## See also

- [Engine Action Registry](../reference/engine-action-registry.md) —
  `@register_action` decorator, `idempotent` parameter, `ActionContext`
- [Pipeline Events — Run-level events](../reference/pipeline-events.md#run-level-events)
  — `pipeline.run.heartbeat_lost` and `pipeline.step.aborted` events
  fired during reclaim
- [Heartbeat Architecture](heartbeat-architecture.md) — how the DB
  heartbeat is refreshed and how the reclaim sweep detects stale rows
