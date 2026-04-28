# Operations Overview

Aurelion ships a small set of long-running background runtimes in addition to the platform HTTP API. Each runtime is a standalone process that consumes from RabbitMQ or sweeps a table on a timer, and is deployed next to the kernel.

| Runtime | Purpose |
|---------|---------|
| `platform_api` | The REST API (`uvicorn` entrypoint). |
| `mq_log_siem_consumer` | Forwards `aurelion.logs` events to the configured SIEM sink. |
| `mq_log_buffer_consumer` | Persists `aurelion.logs` events into the log buffer table. |
| `log_buffer_cleanup` | Periodically truncates old log-buffer rows. |
| `mq_eas_projection_consumer` | Drives incremental Effective Access Store (EAS) projection from inventory events. See [MQ EAS projection consumer](mq-eas-projection-consumer.md). |

All runtimes use `LogService.emit_safe` for lifecycle and error logs. New runtimes do not use `print` — see the logging discipline note on the per-runtime pages.

## Runbooks

One-shot operational procedures live alongside the runtime pages:

| Runbook | Purpose |
|---------|---------|
| [Lake migration](lake-migration-runbook.md) | One-shot PG → Iceberg backfill of `access_artifacts` and `access_facts`, plus the `LAKE_ARTIFACTS_WRITE_BACKEND` flip. |
