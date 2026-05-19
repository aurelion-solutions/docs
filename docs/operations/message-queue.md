# Message Queue Topology

How RabbitMQ is laid out for Aurelion: exchanges, routing keys, queues,
and ownership.

For the semantic split between event types see
[Events and Logs](../concepts/events.md).

## Connection

| Setting | Default | Env override |
|---|---|---|
| Host | `localhost` | `AURELION_MQ__HOST` |
| Port | `5672` | `AURELION_MQ__PORT` |
| Username | `guest` | `AURELION_MQ__USERNAME` |
| Password | `guest` | `AURELION_MQ__PASSWORD` |

AMQP URL: `amqp://<user>:<pwd>@<host>:<port>/`.

The defaults match the `docker-compose.yml` infrastructure under
`aurelion-kernel/`.

## Exchanges

Every exchange is **topic** and **durable**.

| Exchange | Default name | Env override | Owner | Purpose |
|---|---|---|---|---|
| Events | `aurelion.events` | `AURELION_MQ__EVENTS_EXCHANGE` | `platform/events/` | Immutable domain events. Projection consumers (EAS, SoD) read from here. |
| Logs | `aurelion.logs` | `AURELION_MQ__LOGS_EXCHANGE` | `platform/logs/` | Operational telemetry: app logs, audit, inference logs. |
| Connector commands | `aurelion.connectors.commands` | `AURELION_MQ__CONNECTOR_COMMANDS_EXCHANGE` | `engines/reconciliation/connectors/` | Outbound commands from the kernel to connectors. |
| Connector responses | `aurelion.connectors.responses` | `AURELION_MQ__CONNECTOR_RESPONSES_EXCHANGE` | `engines/reconciliation/connectors/` | Connector → kernel responses. |
| Connector registry | `aurelion.connectors.registry` | — | `engines/reconciliation/connectors/` | Connector registration and heartbeat events. |

## Queues

### Log fan-out — `aurelion.logs`

Two durable queues fan out from the logs exchange, each bound to `#`
(every routing key):

| Queue | Consumer | Purpose |
|---|---|---|
| `aurelion.logs.siem` | External SIEM forwarder | Long-term retention, alerting. |
| `aurelion.logs.buffer` | Log Buffer Consumer runtime | Short-term PostgreSQL buffer for operator inspection and the `/log-buffer` read API. |

See [Log Buffer Consumer](mq-log-consumers.md) for the buffer
runtime; see [Log Buffer Cleanup](log-buffer-cleanup.md) for retention.

### Connector registration

The registry exchange is consumed by the registration queue
`aurelion.connectors.registration`, bound to `connector.registered` and
`connector.heartbeat` routing keys.

### Orchestrator matcher

The orchestrator subscribes to the events exchange under
`aurelion.orchestrator.matcher` (configurable via
`AURELION_MQ__ORCHESTRATOR_MATCHER_QUEUE`), with default binding
pattern `#`. This is the path through which event-triggered pipeline
runs are scheduled.

### EAS projection consumer

The Effective Access Store consumer subscribes to the events exchange
through its own queue; see
[MQ EAS Projection Consumer](mq-eas-projection-consumer.md).

## Routing key conventions

### `aurelion.events`

Format: three-segment, lowercase snake_case, e.g.
`inventory.access_fact.created`.

The kernel validates this format on emit. The routing key is the
event's `event_type` field verbatim — no transformation, no prefix
manipulation. Projection consumers bind to patterns over the three
segments (`inventory.*.*`, `reconciliation.run.*`, `pipeline.run.*`).

### `aurelion.logs`

Format: `<component>.<level>`. The component string is sanitized at
emit time (spaces and slashes replaced with hyphens) and the level is
the lowercase log level (`info`, `warning`, `error`, `debug`,
`critical`).

Example: an `engines.reconciliation` log at `INFO` publishes on
`engines.reconciliation.info`.

### `aurelion.connectors.registry`

| Routing key | Producer | Meaning |
|---|---|---|
| `connector.registered` | Connector at startup | Connector advertises itself to the kernel. |
| `connector.heartbeat` | Connector | Periodic liveness signal. |

## Topology declaration

The kernel declares the exchanges and queues it owns at startup. A
test-suite invariant (`test_rabbitmq_topology.py`) covers the
declarations for the events and logs exchanges and the connector
registry, so a topology change in the codebase is caught before it
reaches a broker.

## Operational notes

- **Durability** — all exchanges and queues are durable. A broker
  restart preserves them.
- **No dead-letter exchange yet.** Failed deliveries surface as
  exceptions in the publisher; runtime restart policy handles them.
- **Per-consumer queues are runtime concerns.** Adding a new
  projection consumer creates a new queue, bound to the events
  exchange with a pattern that fits the consumer.
