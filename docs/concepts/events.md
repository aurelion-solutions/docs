# Events and Logs

Aurelion separates two fundamentally different data streams and routes them through different RabbitMQ exchanges.

## Two buses

```
aurelion.events  ──→  projections (EAS, SoD, audit)
aurelion.logs    ──→  SIEM, log buffer
```

This is not just different topics — it is different semantics.

**`aurelion.events`** carries immutable domain facts. Things that happened in the business: `inventory.access_fact.created`, `reconciliation.run.completed`. Projection consumers read this bus and build read models from it (Effective Access Store, SoD).

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

## Effective Access Store (EAS)

The EAS is a read model built from `aurelion.events`. The `mq_eas_projection_consumer` subscribes to the bus and applies changes incrementally, guarded by CAS to prevent duplicates.

The EAS is not the source of truth — it is a projection. The source of truth is the Inventory tables. If the EAS drifts, it can be rebuilt from the event history.

