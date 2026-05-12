# Heartbeat Architecture

The pipeline orchestrator uses two distinct heartbeat mechanisms that
serve different consumers and operate at different layers. Conflating
them leads to operational confusion. This page separates the two,
explains the design choices, and covers the advisory lock pattern
that extends the same philosophy to the beat and matcher processes.

## Two heartbeats, not one

**Work-claim heartbeat** — a timestamp column on the `pipeline_runs`
table (`last_heartbeat_at`), refreshed every 3 seconds by the
executing worker. This heartbeat is consumed by the reclaim sweep: if
the timestamp goes stale for more than 10 seconds, another worker can
claim the run. It is a database-level coordination primitive, invisible
to anything outside Postgres.

**Liveness heartbeat** — an `executor.process.heartbeat` event
published to `aurelion.events` at a configurable interval
(`EXECUTOR_HEARTBEAT_SECONDS`, defaulting to 60 s). This heartbeat is
consumed by operators and monitoring systems. The orchestrator itself
does not consume it — it plays no role in work-claim coordination.

Different layers, different consumers, different failure modes. A
process can be alive (liveness heartbeat flowing) but stuck (work-claim
heartbeat stale, no steps progressing), or dead with its last liveness
event still cached in a dashboard. Neither heartbeat alone tells the
full story.

For the `EXECUTOR_HEARTBEAT_SECONDS` configuration and the
`ExecutorHeartbeatPayload` schema, see
[Runtime Settings](../reference/runtime-settings.md) and
[Pipeline Events — Executor liveness](../reference/pipeline-events.md#executor-liveness).

## Work-claim layer (the DB row)

The work-claim heartbeat exists because `FOR UPDATE SKIP LOCKED` alone
cannot distinguish a live worker from a dead one. The lock is held for
the lifetime of the database session, not the lifetime of the logical
work unit. If the worker process crashes without closing its connection
cleanly, the lock is held until the TCP session times out — which can
take minutes depending on operating system and database configuration.

Adding `last_heartbeat_at` to the claim condition tightens the
detection window to 10 seconds:

```
status = 'pending'
AND (last_heartbeat_at IS NULL
     OR last_heartbeat_at < now() - interval '10 seconds')
```

A row becomes re-claimable as soon as its heartbeat goes stale,
regardless of whether the database session is still open. The stale
run is returned to `pending` by the reclaim sweep, and a new attempt
is inserted. This makes the work queue self-healing: crashed workers
do not hold runs indefinitely.

The same database that owns the domain state also owns the
coordination state. There is no second system to keep in sync,
no split-brain between the lock store and the work queue.

## Liveness layer (the MQ event)

The DB heartbeat is invisible to anything outside Postgres. An
operator monitoring the system cannot see whether a worker is alive
by querying `pipeline_runs` — they would need to know which rows are
supposed to be claimed and whether those timestamps are moving.

The liveness heartbeat solves this by publishing a structured event
with a short, human-interpretable payload: `worker_id`,
`slot_index`, `started_at`, `pipelines_loaded`. No PII, no business
state. The `worker_id` is a synthetic `<hostname>-<pid>-<slot>` string.

The liveness event rides the existing `aurelion.events` exchange with
routing key `executor.process.heartbeat`. No new exchange or binding
is required. Failed emissions are caught and logged as WARNING; the
executor loop continues — a monitoring gap is preferable to a crashed
executor.

## Trade-offs vs SKIP LOCKED only

Without the DB heartbeat, the reclaim window depends entirely on TCP
timeout semantics. In practice this means:

- A crashed worker holds its work item for minutes (Linux TCP keepalive
  defaults are 2 hours without tuning; even with tuning, a dead process
  that closed the socket cleanly releases the lock immediately, but a
  hard crash may not).
- No forensic trail: there is no record of which worker held the run
  or when the session closed.

The 10-second reclaim window is a deliberate tightening. The
`EXECUTOR_DRAIN_TIMEOUT_SECONDS` setting (minimum 15 s, default 60 s)
ensures a gracefully shutting down executor has enough time to finish
its current step before the reclaim sweep would falsely reclaim it.
This relationship — drain timeout must exceed reclaim threshold by at
least 5 seconds — is enforced in the bootstrap with a WARNING clamp.

## Trade-offs vs ZooKeeper / etcd / Redis

Distributed coordination systems like ZooKeeper, etcd, and Redis
provide strong consistency guarantees for leader election and
distributed locking. The orchestrator does not use any of them.
The rationale:

Each of those systems adds an external dependency that must itself be
highly available, monitored, upgraded, and kept consistent with the
Postgres state they are supposed to coordinate. For the current
volume — at most thousands of pending runs — the overhead of a
second consensus system outweighs the benefit.

Postgres `FOR UPDATE SKIP LOCKED` composes naturally with the tables
that hold the actual domain state. Schema migrations, status updates,
event emission, and work-claim coordination all happen in the same
database and can participate in the same transactions. This locality
is the core architectural advantage.

The cost is harder cross-region federation: if the orchestrator is
ever deployed across multiple Postgres primaries, the work-claim
layer will need to be redesigned. That trade-off is documented and
accepted. The work-claim layer is isolated to `runner.py` and
`service.py`; swapping it for a distributed primitive later is a
bounded change.

## Beat and matcher locks

The beat and matcher processes extend the same philosophy to prevent
duplicate schedule firing and duplicate MQ consumption across API
replicas.

**`_BEAT_LOCK_KEY`** — a Postgres advisory lock acquired per tick in
`beat.py`. Only one API replica fires schedule triggers in any given
10-second window. The lock is held for the duration of the tick
commit and released afterward, so replicas take turns rather than
one holding the lock indefinitely.

**`_MATCHER_LOCK_KEY`** — a session-level advisory lock acquired at
startup in `matcher.py`. Only one replica consumes from the
`aurelion.events` exchange at a time. A second replica that fails
to acquire the lock enters a warm-standby sleep loop (1 s) until
the lock is released.

Both constants are defined in their respective modules and documented
in ARCH_CONTEXT. They are distinct keys — no collision between beat
and matcher — and new advisory locks must be documented before use to
prevent accidental reuse of an existing key value.

The same primitive (Postgres advisory locks), the same operational
philosophy: coordinate via the database, keep the number of systems
small, accept bounded blast radius.

## See also

- [Pipeline Events](../reference/pipeline-events.md) — `executor.process.heartbeat`
  routing key, payload schema, and `pipeline.run.heartbeat_lost`
- [Runtime Settings](../reference/runtime-settings.md) — `EXECUTOR_HEARTBEAT_SECONDS`
  and `EXECUTOR_DRAIN_TIMEOUT_SECONDS` bootstrap env vars
- [Idempotency and Reclaim](idempotency-and-reclaim.md) — what the
  reclaim sweep does when it detects a stale heartbeat
