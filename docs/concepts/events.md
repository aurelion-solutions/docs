# Events and Logs

Aurelion separates two fundamentally different data streams and routes them through different RabbitMQ exchanges.

## Two buses

```
aurelion.events  ──→  projections (EAS, SoD, audit)
aurelion.logs    ──→  SIEM, log buffer
```

This is not just different topics — it is different semantics.

**`aurelion.events`** carries immutable domain facts. Things that happened in the business: `inventory.access_fact.created`, `reconciliation.run.started`, `reconciliation.delta.created`, `reconciliation.run.completed`, `reconciliation.run.failed`. Projection consumers read this bus and build read models from it (Effective Access Store, SoD).

**`aurelion.logs`** carries operational telemetry. Diagnostics, tracing, SIEM feed. It is not a source of truth for business state.

## Choosing a bus

One question: *will a projection consume this?*

- Yes → `aurelion.events`, via `EventService.emit(...)`
- No → `aurelion.logs`, via `LogService`

If you are not sure — it is probably a log.

## EventEnvelope

All events on `aurelion.events` travel in a standard envelope:

```json
{
  "event_id": "...",
  "event_type": "inventory.access_fact.created",
  "occurred_at": "2024-01-15T10:30:00Z",
  "correlation_id": "...",
  "payload": { ... }
}
```

`event_type` is also the RabbitMQ routing key. Format: three segments, lowercase snake_case.

## Correlation ID

Every event and every log record carries a `correlation_id`. It is the thread that ties together everything that happens because of a single trigger — one HTTP request, one scan run, one consumer message.

The kernel populates `correlation_id` automatically from per-request context. For HTTP traffic, that context is seeded by middleware that reads the `X-Correlation-ID` request header (or generates a UUID if the caller did not send one) and echoes it back in the response. Anything emitted while handling the request — domain events on `aurelion.events`, log records on `aurelion.logs` — inherits that ID without the service layer having to thread it through every call.

External callers (Engineering Studio, the CLI, aurelion-lens) should propagate their own correlation IDs through `X-Correlation-ID` so a single user action stays joinable across services.

Background workers (consumers, schedulers) seed their own correlation context when they start processing a unit of work; the same propagation applies — every event and log emitted within that unit shares the ID.

## Who emits

Only `service.py` emits events. Never models, never routes.py, never capability orchestrators directly — only when they act as a service layer.

This is not just a convention — it is an invariant. If an event is emitted from two places, that is a bug: either deduplicate or merge the call sites.

The single-emitter rule is enforced per event family. For example, `inventory.access_fact.{created,updated,revoked,reactivated}` is emitted **only** from `capabilities/sync_apply/service.py` — `AccessFactService` mutating methods do not emit. The rationale: `normalized.access_facts` is owned by Iceberg via `lake_writer`, and `SyncApplyService` is the only path that writes to it.

## Per-row vs per-batch

Most domain events are per-row: one row created or changed, one event. Bulk-ingest paths emit a single per-batch event instead — for example, `inventory.access_artifacts.batch_ingested` is fired exactly once per bulk upsert or bulk tombstone, with `ingested_count`, `tombstoned_count`, `snapshot_id`, and `backend` in the payload. Per-row events are suppressed for the rows in that batch. Projection consumers must therefore handle both shapes when they care about a given entity.

The single-emit-site rule still holds: bulk endpoints under `/access-artifacts` do not emit directly — the ingest capability owns the emission.

## Reconciliation event ordering

A reconciliation run emits up to four events on `aurelion.events`. They share a `run_id` and `correlation_id`; their `occurred_at` timestamps reflect the actual lifecycle moments inside the run, not the publish order on the bus.

Successful run (`mode=review` or `dry_run`):

```
reconciliation.run.started      occurred_at = run.started_at
reconciliation.delta.created    occurred_at = after delta persistence
reconciliation.run.completed    occurred_at = run.finished_at
```

Failed run:

```
reconciliation.run.started      occurred_at = run.started_at
reconciliation.run.failed       occurred_at = failure time, payload has `error`
```

Consumers that care about ordering must sort by `occurred_at` from the envelope. The publish order is best-effort and for practical purposes matches the lifecycle order, but the timestamp is the contract.

## Access fact events

`inventory.access_fact.{created,updated,revoked,reactivated}` is fired per delta item by `SyncApplyService` during apply. Every payload carries three traceability fields in addition to the per-fact data:

| Field | Why it is there |
|---|---|
| `delta_item_id` | The `reconciliation_delta_items` row that produced this fact change. Lets a consumer join the event back to the originating diff and to the human review trail. |
| `snapshot_id` | The Iceberg snapshot id of `normalized.access_facts` after the apply batch. Lets a consumer reproduce the exact lake state the event corresponds to. `null` only on crash-recovered items where no new write was needed. |
| `reconciliation_run_id` | The reconciliation run that staged the delta. Multiple events with the same `reconciliation_run_id` are part of the same logical sync. |

The `actor_kind` is `CAPABILITY` and the `actor_id` is `capabilities.sync_apply`. Recovered-already-written items still emit the event — the user-visible contract is "fact created/updated/revoked", regardless of whether the write happened on this attempt or was carried over from a previous crashed apply.

## Effective Access Store (EAS)

The EAS is a read model built from `aurelion.events`. The `mq_eas_projection_consumer` subscribes to the bus and applies changes incrementally, guarded by CAS to prevent duplicates.

The EAS is not the source of truth — it is a projection. The source of truth is the Inventory tables. If the EAS drifts, it can be rebuilt from the event history.

