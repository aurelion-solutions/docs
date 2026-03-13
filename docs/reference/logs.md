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
| `component` | Emitting component (e.g. `capabilities.reconciliation`) |
| `payload` | Structured data |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/logs?limit=<n>` | Read recent log records |

## CLI

| Command | Description |
|---|---|
| `al logs read` | Read recent logs (default limit: 100) |
| `al logs read --limit <n>` | Read with custom limit |
