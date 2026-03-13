# MQ EAS Projection Consumer

**Status:** current — Phase 10 Step 4 forward-pointer (see [Forward-pointer: Phase 10](#forward-pointer-phase-10)).

A standalone RabbitMQ consumer runtime that drives **incremental** Effective Access Store (EAS) projection off inventory domain events. One inventory event (an `access_fact.*` or `initiative.*` change) produces one call to `EffectiveAccessProjectionService.apply_incremental_change`, which upserts or tombstones the affected rows in `effective_grants`.

Source: `aurelion-kernel/src/runtimes/mq_eas_projection_consumer/`.

## What it does

For every relevant inventory event the consumer:

1. Decodes the `LogEvent` envelope from the MQ body.
2. Maps the `event_type` to an `IncrementalApplyKind` (`upsert`, `invalidate_fact`, or `invalidate_initiative`).
3. Extracts `access_fact_id` (for fact-scoped events) or `initiative_id` (for `initiative.expired`) from the event payload.
4. Opens a fresh async session, calls `apply_incremental_change(...)`, commits.

The apply method is **idempotent** and **order-safe**: it guards each row with a compare-and-swap on `observed_at`, so out-of-order re-delivery converges to the newest observation without cross-row locking.

The full pipeline — raw ACL ingest → Phase 08 normalization → `access_fact.*` / `initiative.*` events → this consumer's decode path → `effective_grants` rows → read API — is pinned end-to-end by `aurelion-kernel/src/capabilities/effective_access/tests/test_e2e_pipeline.py` (Phase 09 Step 7). The test does not exercise a live RabbitMQ broker: it tails the real `FileLogSink` JSONL output and feeds each line into `_handle_message_async` as bytes, which is byte-identical to what the broker would deliver.

### Events consumed

Subscribed `event_type` values (filtered after decode; other event types on the same bindings are ignored silently):

| Event type | Mapped `IncrementalApplyKind` | Routing key extracted |
|------------|-------------------------------|------------------------|
| `access_fact.created` | `UPSERT` | `access_fact_id` |
| `access_fact.updated` | `UPSERT` | `access_fact_id` |
| `access_fact.invalidated` | `INVALIDATE_FACT` | `access_fact_id` |
| `initiative.created` | `UPSERT` | `access_fact_id` |
| `initiative.expired` | `INVALIDATE_INITIATIVE` | `initiative_id` (tombstones only the grants of the expired initiative, not every grant sharing the parent `AccessFact`) |

`access_fact.*` events and `initiative.created` MUST carry a top-level `access_fact_id` (UUID string). `initiative.expired` events MUST carry a top-level `initiative_id` (UUID string). Phase 09 Step 5 extended `initiative.expired` payloads to carry both `access_fact_id` and `initiative_id` — the consumer uses `initiative_id` for routing and ignores `access_fact_id` on this path.

### Events emitted

**Domain event** (emitted from the service, pre-commit, exactly once per apply call):

| Event type | Level | Payload highlights |
|------------|-------|--------------------|
| `eas.projection.completed` | INFO | `mode` (`batch` / `incremental`), `change_kind`, `triggered_by` (`consumer` in this runtime), `causation_event_id`, `rows_inserted`, `rows_updated`, `rows_skipped`, `rows_tombstoned`, `pairs_projected` |

`rows_tombstoned` folds every tombstone produced by the apply call into one counter: CAS-driven scope-wide tombstones on `invalidate_fact` / `invalidate_initiative`, **and** set-difference tombstones on `upsert` (rows whose `source_initiative_id` is no longer in the fact's live initiative set at reprojection time). A non-zero `rows_tombstoned` on `change_kind='upsert'` is expected, not a bug.

**Operational events** (emitted by the consumer handler itself, not domain events — they describe the consumer's own lifecycle, not a change in EAS state):

| Event type | Level | Trigger |
|------------|-------|---------|
| `eas.projection.consumer.started` | INFO | Process startup, after MQ topology is declared |
| `eas.projection.consumer.parse_error` | ERROR | Body is not valid JSON or does not validate as `LogEvent` |
| `eas.projection.consumer.missing_fact_id` | WARNING | Well-formed `LogEvent` (fact-scoped event) but `payload.access_fact_id` is missing, non-string, or not a valid UUID |
| `eas.projection.consumer.missing_initiative_id` | WARNING | Well-formed `LogEvent` (`initiative.expired`) but `payload.initiative_id` is missing, non-string, or not a valid UUID |
| `eas.projection.consumer.apply_failed` | ERROR | `apply_incremental_change` raised; emitted **after** `session.rollback()`, deliberately outside the business transaction |

Component for all four is `eas.projection.consumer`.

## How to run

From the kernel root (`aurelion-kernel/`):

```bash
python -m src.runtimes.mq_eas_projection_consumer.main
```

The process is long-running. It blocks on `channel.start_consuming()` and acks every message — see [Delivery semantics](#delivery-semantics).

Typical deployment: one replica. Horizontal scale-out is safe in principle (the apply is idempotent and CAS-guarded) but not exercised in Phase 09; keep it at one replica unless you have a reason to change that.

## Configuration

Environment variables read on startup:

| Variable | Default | Description |
|----------|---------|-------------|
| `AURELION_RABBITMQ_HOST` | `localhost` | RabbitMQ host |
| `AURELION_RABBITMQ_PORT` | `5672` | RabbitMQ port |
| `AURELION_RABBITMQ_USERNAME` | unset | Optional; falls back to `guest` if both username and password are unset |
| `AURELION_RABBITMQ_PASSWORD` | unset | Optional; pairs with `AURELION_RABBITMQ_USERNAME` |
| `AURELION_LOGS_EXCHANGE` | `aurelion.logs` | Topic exchange to subscribe to. Same exchange the logs bus uses today — this consumer is a second subscriber against it. |
| `AURELION_EAS_PROJECTION_QUEUE` | `eas.projection.incremental` | Durable queue name owned by this consumer. |
| `AURELION_EAS_PROJECTION_BINDINGS` | `inventory.access_facts.*,inventory.initiatives.*` | Comma-separated routing-key patterns for the queue. Patterns match the real Phase-08 producer routing keys (`inventory.access_facts.info`, `inventory.access_facts.warning`, `inventory.initiatives.info`, `inventory.initiatives.warning`). |
| `AURELION_LOG_SINK_PROVIDER` | `file` | Log sink for the consumer's own lifecycle and operational events. Same provider catalog as the rest of the kernel — see [Logs](../reference/logs.md). |

The queue and exchange are both declared **durable**. The consumer owns its own queue; there are no companion queues.

## Delivery semantics

**Ack-and-log.** Every message is `basic_ack`'d unconditionally after the handler returns, regardless of outcome. Failure paths emit operational events instead of re-queuing:

| Outcome | Session | Message |
|---------|---------|---------|
| Happy path (apply succeeded) | `commit()` | ack |
| Parse error (body not JSON / not a valid `LogEvent`) | session not opened | ack (after `parse_error` log) |
| Irrelevant event type (e.g. `subject.created`, any event type not in the consumed set) | session not opened | ack (silent — noise filter) |
| Missing / malformed `access_fact_id` (fact-scoped events) | session not opened | ack (after `missing_fact_id` log) |
| Missing / malformed `initiative_id` (`initiative.expired`) | session not opened | ack (after `missing_initiative_id` log) |
| Apply raised | `rollback()`, then emit `apply_failed` | ack |

Rationale: the existing `aurelion.logs` exchange is a log bus, not a transactional event bus. Re-delivery semantics (DLQ, retry backoff) belong to the new `aurelion.events` exchange landing in Phase 10. Until then, a poisoned message is dropped after an ERROR log; recovery for a genuinely missed update is a full-rebuild (reprojection) path, which is not yet exposed as an operational endpoint.

**No DLQ. No retry. No backoff.** A dedicated full-rebuild endpoint is not shipped yet; if you need to reconcile EAS after a consumer outage today, you have to reproject via the service layer rather than replay the log exchange.

## Error handling discipline

Three rules on the handler:

1. **Parse errors** (invalid JSON, invalid `LogEvent`) → emit `eas.projection.consumer.parse_error` at ERROR with a `raw_preview` (first 200 bytes of the body), ack, return. The message is effectively dead-lettered to the operational log; the runtime does not maintain a separate DLQ queue.
2. **Missing routing key** → for fact-scoped events, emit `eas.projection.consumer.missing_fact_id` at WARNING; for `initiative.expired`, emit `eas.projection.consumer.missing_initiative_id` at WARNING. Ack, return. This is a poison message: the producer violated the payload contract, so retry cannot help.
3. **Apply failed** (anything raised inside `apply_incremental_change` or `session.commit()`) → `await session.rollback()`, then emit `eas.projection.consumer.apply_failed` at ERROR with `payload={'scope_key', 'event_type', 'exception_type'}`, ack, return. The emission is deliberately **outside** the rolled-back transaction so that the operator log survives the rollback.

### Logging discipline

All emissions go through `LogService.emit_safe`. Forbidden in this runtime: `print`, `logging.getLogger`, `structlog`. Startup visibility is via `emit_safe` only — if the log pipeline is not yet reachable at startup (network failure), `emit_safe` swallows the failure and the process proceeds; operators observe the process alive via `ps` / `docker ps`.

This differs from the older `mq_log_siem_consumer` and `mq_log_buffer_consumer`, which still use `print(..., file=sys.stderr)` because they pre-date the LogService-only discipline. New runtimes ship without `print`.

### Event emission placement (invariant)

The four operational events (`parse_error`, `missing_fact_id`, `missing_initiative_id`, `apply_failed`) are emitted from the handler, not from a `service.py`. This does **not** violate the "only `service.py` emits events" invariant: those are **operational / observability** logs describing the consumer process itself, not domain events describing a change in EAS state. The only domain event emitted on this path is `eas.projection.completed`, which remains inside `EffectiveAccessProjectionService.apply_incremental_change` (pre-commit, post-flush), as the invariant requires.

## Forward-pointer: Phase 10

Phase 10 Step 4 rewrites this consumer to subscribe to the new `aurelion.events` exchange. Only the transport boundary changes — **the runtime itself stays**:

- The exchange name moves from `aurelion.logs` to `aurelion.events`.
- The routing-key patterns in `AURELION_EAS_PROJECTION_BINDINGS` change to the Phase 10 event-envelope routing keys.
- The envelope-decoding logic in `handler._handle_message_async` changes (new envelope schema).

The slice-local apply API (`EffectiveAccessProjectionService.apply_incremental_change`) is stable across that rewrite — callers do not need to change. Keep that boundary in mind when editing the handler: the decode step is the seam Phase 10 swaps; everything downstream of it is already Phase-10 stable.

### Projection gap (accepted, temporary)

Phase 10 Step 2 migrated the first producer — `inventory/access_facts` — onto `aurelion.events` with three-segment routing keys (`inventory.access_fact.created`, `inventory.access_fact.invalidated`). This consumer has **not** been rebound yet: it still subscribes to `aurelion.logs` with the old two-segment whitelist (`access_fact.created`, `access_fact.invalidated`). Between the Step 2 merge and the Step 4 consumer rebind, the EAS read model does not receive `access_fact` updates through this path.

This is an accepted state, not a bug, under the following conditions:

- pre-prod only — no production consumer reads the EAS projection today
- direct reads from the `access_facts` table via REST continue to work (the inventory table is the source of truth; the projection is a derived read model)
- no external SIEM or downstream analytics subscribes to the EAS projection output today
- dev data is recreatable by replaying reconciliation / ACL ingest after the rebind

Events emitted by `AccessFactService` during this window are **not** replayed into the projection after Step 4 lands. If a pre-prod environment needs to catch up, rerun the reconciliation pipeline end-to-end — that re-emits `inventory.access_fact.created` onto the new bus, which the rebound consumer then picks up. No catch-up queue or event replay machinery is planned.

The other inventory producers (`initiatives` in particular) remain on `aurelion.logs` with their old two-segment event types until the batch producer migration. While they stay there, this consumer keeps processing them unchanged — only the `access_fact` path is split across the two buses right now.
