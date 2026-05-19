# Logs

Read access to the platform operational log buffer. Logs flow through `aurelion.logs` and are buffered before forwarding to SIEM or external systems. The read endpoint surfaces recent log records.

Note: only the `file` provider supports reading. All other providers (elk, loki, splunk, etc.) are write-only stubs and will return 501 on read.

## Log record fields

| Field | Notes |
|---|---|
| `event_type` | Log event type |
| `level` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `message` | Human-readable message |
| `timestamp` | When the event was logged |
| `component` | Emitting component (e.g. `engines.reconciliation`) |
| `correlation_id` | Request/work-unit identifier; seeded from `X-Correlation-ID` for HTTP-driven logs |
| `payload` | Structured data |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/logs?limit=<n>` | Read recent log records via the configured provider (only the `file` provider supports read; others return `501`). |
| `GET` | `/api/v0/platform/logs?limit=<n>&level=<lvl>` | Tail recent records from the in-memory log buffer kept on the platform API process. `1 <= limit <= 500`. |
| `GET` | `/api/v0/log-buffer` | Query the PostgreSQL log buffer with filters (correlation id, target, initiator, actor, level, time bounds). |

### `GET /api/v0/log-buffer`

Query parameters:

| Name | Notes |
|---|---|
| `correlation_id` | Filter by correlation id |
| `target_type` / `target_id` | Pair; both required when one is set |
| `initiator_type` / `initiator_id` | Pair |
| `actor_type` / `actor_id` | Pair |
| `level` | One of `info`, `warning`, `error`, `debug`, `critical` |
| `from_ts` / `to_ts` | ISO 8601 timestamp bounds (inclusive) |
| `order` | `asc` or `desc` (default `desc`) |
| `limit` | `1..1000` (default `100`) |

## CLI

| Command | Description |
|---|---|
| `al logs read` | Read recent logs via the configured provider (default limit: 100). Returns `501` if the provider is write-only. |
| `al logs read --limit <n>` | Read with custom limit. |
| `al logs tail` | Tail the platform in-memory log buffer (`/api/v0/platform/logs`). `--limit` (1..500, default 50), `--level <lvl>`. |
| `al logs buffer` | Query the PostgreSQL log buffer (`/api/v0/log-buffer`) with rich filters. Supports `--correlation-id`, `--target-type`/`--target-id`, `--initiator-type`/`--initiator-id`, `--actor-type`/`--actor-id`, `--level`, `--from-ts`, `--to-ts`, `--order`, `--limit`. |
