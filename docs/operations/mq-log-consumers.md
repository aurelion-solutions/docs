# Log MQ Consumers

Two consumers handle the `aurelion.logs` exchange: one persists logs to the database buffer, the other forwards them to an external SIEM.

---

## mq_log_buffer_consumer

Reads from `aurelion.logs` and writes each log event into the `log_buffer` table. The buffer is the source for `GET /api/v0/logs` and for the Engineering Studio log stream.

### Start

```bash
python -m src.runtimes.mq_log_buffer_consumer.main
```

### Configuration

| Variable | Default | Description |
|---|---|---|
| `AURELION_RABBITMQ_HOST` | `localhost` | RabbitMQ host |
| `AURELION_RABBITMQ_PORT` | `5672` | RabbitMQ port |
| `AURELION_RABBITMQ_USERNAME` | — | Optional |
| `AURELION_RABBITMQ_PASSWORD` | — | Optional |
| `AURELION_LOGS_EXCHANGE` | `aurelion.logs` | Exchange to consume |
| `DATABASE_URL` | required | PostgreSQL DSN for buffer writes |

### Delivery semantics

Ack-and-log: every message is acknowledged after processing, regardless of outcome. Failed writes are logged and dropped — there is no retry or DLQ.

---

## mq_log_siem_consumer

Reads from `aurelion.logs` and forwards each event to the configured external SIEM provider (Splunk, ELK, Loki, QRadar, etc.).

### Start

```bash
python -m src.runtimes.mq_log_siem_consumer.main
```

### Configuration

| Variable | Default | Description |
|---|---|---|
| `AURELION_RABBITMQ_HOST` | `localhost` | RabbitMQ host |
| `AURELION_RABBITMQ_PORT` | `5672` | RabbitMQ port |
| `AURELION_RABBITMQ_USERNAME` | — | Optional |
| `AURELION_RABBITMQ_PASSWORD` | — | Optional |
| `AURELION_LOGS_EXCHANGE` | `aurelion.logs` | Exchange to consume |
| `AURELION_LOG_SINK_PROVIDER` | `file` | SIEM provider to forward to |

### Delivery semantics

Same as `mq_log_buffer_consumer`: ack-and-log, no retry.

### Supported providers

| Provider | Read support | Notes |
|---|---|---|
| `file` | Yes | Local JSONL file; dev only |
| `elk` | No (stub) | Write-only |
| `splunk` | No (stub) | Write-only |
| `loki` | No (stub) | Write-only |
| `qradar` | No (stub) | Write-only |

Production deployments should configure a real SIEM provider. The `file` provider is for local development only.
