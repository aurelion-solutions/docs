# Runtime Settings

Catalogue of operator-tunable knobs for the Aurelion platform. Covers both
database-backed runtime keys (mutable at runtime without restart) and
bootstrap-tier environment variables (read at process start).

## Runtime settings table

Runtime settings are stored in the `runtime_settings` PostgreSQL table and
loaded by `RuntimeSettingsService`. The service caches the snapshot and
refreshes it periodically; consumers receive the latest value without restarting.

API endpoint for updating a key:

```
PUT /api/v0/runtime-settings/{key}
```

Request body: `{"value": "<string-serialized value>"}`.
The service coerces the string to the declared type and validates it against
`RuntimeSettingsConfig` field constraints before persisting.

## Runtime keys

Default values and constraints are defined in `RuntimeSettingsConfig` in
`aurelion-kernel/src/platform/runtime_settings/schemas.py`.

| Key | Default | Range / constraint | Effect |
|---|---|---|---|
| `log_buffer_retention_seconds` | `3600` | integer | How long log entries are retained in the buffer before cleanup |
| `lake_pool_size` | `4` | integer | DuckDB connection pool size for the data lake |
| `lake_acquire_timeout_seconds` | `5.0` | float | Max seconds to wait for a pool connection before timing out |
| `lake_pg_any_array_max_size` | `25000` | integer | Maximum array size for Postgres `ANY(ARRAY[...])` pushdown |
| `lake_read_page_size` | `1000` | 1..5000 | Rows fetched per page when streaming lake data |
| `reconciliation_fetch_batch_size` | `5000` | 1..50000 | Batch size for reconciliation delta fetch |
| `llm_max_loaded_models` | `2` | >= 1 | Maximum concurrently loaded LLM models |
| `llm_max_messages` | `32` | >= 1 | Maximum messages per LLM conversation context |
| `llm_max_chars_per_message` | `32000` | >= 1 | Maximum characters per message in LLM context |
| `llm_max_total_chars` | `128000` | >= 1 | Maximum total characters across all messages in LLM context |

## Bootstrap env vars (executor node)

Read before the database connection is established, from
`aurelion-kernel/src/runtimes/platform_executor_node/main.py`. Set in `.env`
or your secret manager.

| Variable | Default | Minimum | Effect |
|---|---|---|---|
| `EXECUTOR_HEARTBEAT_SECONDS` | `60` | `1` | Interval in seconds between `executor.process.heartbeat` events. Values below `1` are clamped to `1` with a WARNING log |
| `EXECUTOR_DRAIN_TIMEOUT_SECONDS` | `60` | `RECLAIM_THRESHOLD + 5` (≈ 15) | Grace period in seconds after SIGTERM before the executor exits. Must exceed the stale-reclaim threshold (10 s) by at least 5 s; values too low are clamped with a WARNING log |

## Bootstrap env vars (platform API)

The platform API bootstrap variables (`DATABASE_URL`, `RABBITMQ_URL`,
`SECRET_*`, etc.) are documented in `.env.example` in `aurelion-kernel/`.
They are not re-enumerated here — `.env.example` is the single source of truth.

## Out of scope

Multi-slot executor concurrency and the HTTP health endpoint are not implemented.
The executor runs a single slot (`slot_index=0`) and must not be configured otherwise.

## Source of truth

- `aurelion-kernel/src/platform/runtime_settings/schemas.py` — `RuntimeSettingsConfig`
- `aurelion-kernel/src/runtimes/platform_executor_node/main.py` — executor bootstrap env-var parsing
