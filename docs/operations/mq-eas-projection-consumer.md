# MQ EAS Projection Consumer

A standalone RabbitMQ consumer runtime that drives **incremental** Effective
Access Store (EAS) projection from inventory domain events. One inventory
event (`access_fact.*` or `initiative.*` change) produces one call to
`EffectiveAccessProjectionService.apply_incremental_change`, which upserts
or tombstones the affected rows in `effective_grants`.

Source: `aurelion-kernel/src/runtimes/mq_eas_projection_consumer/`.

## What it does

For every relevant inventory event the consumer:

1. Decodes the event envelope from the MQ body.
2. Maps the `event_type` to an `IncrementalApplyKind` (`upsert`, `invalidate_fact`, or `invalidate_initiative`).
3. Extracts `access_fact_id` (for fact-scoped events) or `initiative_id` (for `initiative.expired`) from the event payload.
4. Opens a fresh async session, calls `apply_incremental_change(...)`, commits.

The apply method is idempotent and order-safe: it guards each row with a
compare-and-swap on `observed_at`, so out-of-order re-delivery converges
to the newest observation without cross-row locking.

### Events consumed

Subscribed `event_type` values (filtered after decode; other event types
on the same bindings are ignored silently):

| Event type | Mapped `IncrementalApplyKind` | Routing key extracted |
|------------|-------------------------------|------------------------|
| `access_fact.created` | `UPSERT` | `access_fact_id` |
| `access_fact.updated` | `UPSERT` | `access_fact_id` |
| `access_fact.invalidated` | `INVALIDATE_FACT` | `access_fact_id` |
| `initiative.created` | `UPSERT` | `access_fact_id` |
| `initiative.expired` | `INVALIDATE_INITIATIVE` | `initiative_id` (tombstones only the grants of the expired initiative, not every grant sharing the parent `AccessFact`) |

`access_fact.*` events and `initiative.created` MUST carry a top-level
`access_fact_id` (UUID string). `initiative.expired` events MUST carry a
top-level `initiative_id` (UUID string).

### Events emitted

**Domain event** (emitted from the service, pre-commit, exactly once per
apply call):

| Event type | Level | Payload highlights |
|------------|-------|--------------------|
| `eas.projection.completed` | INFO | `mode` (`batch` / `incremental`), `change_kind`, `triggered_by` (`consumer` in this runtime), `causation_event_id`, `rows_inserted`, `rows_updated`, `rows_skipped`, `rows_tombstoned`, `pairs_projected` |

`rows_tombstoned` folds every tombstone produced by the apply call into
one counter: scope-wide tombstones on `invalidate_fact` /
`invalidate_initiative`, **and** set-difference tombstones on `upsert`
(rows whose `source_initiative_id` is no longer in the fact's live
initiative set at reprojection time). A non-zero `rows_tombstoned` on
`change_kind='upsert'` is expected, not a bug.

**Operational events** (consumer lifecycle, not domain events):

| Event type | Level | Trigger |
|------------|-------|---------|
| `eas.projection.consumer.started` | INFO | Process startup, after MQ topology is declared |
| `eas.projection.consumer.parse_error` | ERROR | Body is not valid JSON or does not validate as the expected envelope |
| `eas.projection.consumer.missing_fact_id` | WARNING | Well-formed envelope (fact-scoped event) but `payload.access_fact_id` is missing, non-string, or not a valid UUID |
| `eas.projection.consumer.missing_initiative_id` | WARNING | Well-formed envelope (`initiative.expired`) but `payload.initiative_id` is missing, non-string, or not a valid UUID |
| `eas.projection.consumer.apply_failed` | ERROR | `apply_incremental_change` raised; emitted **after** `session.rollback()`, deliberately outside the business transaction |

Component for all four is `eas.projection.consumer`.

## How to run

From the kernel root (`aurelion-kernel/`):

```bash
python -m src.runtimes.mq_eas_projection_consumer.main
```

The process is long-running. It blocks on `channel.start_consuming()` and
acks every message — see [Delivery semantics](#delivery-semantics).

Typical deployment: one replica. Horizontal scale-out is safe in
principle (the apply is idempotent and CAS-guarded) but not exercised
under production load — keep it at one replica unless you have a reason
to change that.

## Configuration

Environment variables read on startup:

| Variable | Default | Description |
|----------|---------|-------------|
| `AURELION_RABBITMQ_HOST` | `localhost` | RabbitMQ host |
| `AURELION_RABBITMQ_PORT` | `5672` | RabbitMQ port |
| `AURELION_RABBITMQ_USERNAME` | unset | Optional; falls back to `guest` if both username and password are unset |
| `AURELION_RABBITMQ_PASSWORD` | unset | Optional; pairs with `AURELION_RABBITMQ_USERNAME` |
| `AURELION_LOGS_EXCHANGE` | `aurelion.logs` | Topic exchange to subscribe to. |
| `AURELION_EAS_PROJECTION_QUEUE` | `eas.projection.incremental` | Durable queue name owned by this consumer. |
| `AURELION_EAS_PROJECTION_BINDINGS` | `inventory.access_facts.*,inventory.initiatives.*` | Comma-separated routing-key patterns for the queue. |
| `AURELION_LOG_SINK_PROVIDER` | `file` | Log sink for the consumer's own lifecycle and operational events. Same provider catalog as the rest of the kernel — see [Logs](../reference/logs.md). |

The queue and exchange are both declared **durable**. The consumer owns
its own queue; there are no companion queues.

## Delivery semantics

**Ack-and-log.** Every message is `basic_ack`'d unconditionally after the
handler returns, regardless of outcome. Failure paths emit operational
events instead of re-queuing:

| Outcome | Session | Message |
|---------|---------|---------|
| Happy path (apply succeeded) | `commit()` | ack |
| Parse error | session not opened | ack (after `parse_error` log) |
| Irrelevant event type | session not opened | ack (silent — noise filter) |
| Missing / malformed `access_fact_id` (fact-scoped events) | session not opened | ack (after `missing_fact_id` log) |
| Missing / malformed `initiative_id` (`initiative.expired`) | session not opened | ack (after `missing_initiative_id` log) |
| Apply raised | `rollback()`, then emit `apply_failed` | ack |

**No DLQ. No retry. No backoff.** A dedicated full-rebuild endpoint is not
shipped yet; to reconcile EAS after a consumer outage, rerun the
reconciliation pipeline end-to-end — that re-emits `access_fact` events
that this consumer then picks up.

## Failure modes

| Symptom | Likely cause | Action |
|---|---|---|
| Consumer alive but `effective_grants` not updating | Wrong `AURELION_EAS_PROJECTION_BINDINGS` patterns; events arriving on a routing key the queue is not bound to. | Inspect the RabbitMQ queue bindings; align with the producer's routing keys. |
| `parse_error` log entries | Producer changed the envelope schema or sent invalid JSON. | Confirm producers use the current envelope; the consumer drops these messages silently after the log entry. |
| `apply_failed` log entries | Database error during apply (FK violation, constraint, transient connection loss). | Check the kernel DB; the consumer continues processing the next message. |
| Lag growing | Consumer paused or single replica saturated. | Check process is alive (`ps` / `docker ps`); the consumer does not drop messages — they sit in the queue until consumed. |

For the conceptual model of EAS projection, see [Access Analysis concept](../concepts/access-analysis.md).
