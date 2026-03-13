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

## Who emits

Only `service.py` emits events. Never models, never routes.py, never capability orchestrators directly — only when they act as a service layer.

This is not just a convention — it is an invariant. If an event is emitted from two places, that is a bug: either deduplicate or merge the call sites.

## Effective Access Store (EAS)

The EAS is a read model built from `aurelion.events`. The `mq_eas_projection_consumer` subscribes to the bus and applies changes incrementally, guarded by CAS to prevent duplicates.

The EAS is not the source of truth — it is a projection. The source of truth is the Inventory tables. If the EAS drifts, it can be rebuilt from the event history.

