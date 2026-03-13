# Log Buffer Cleanup Runtime

A periodic sweep that truncates old rows from the `log_buffer` table. Without this, the buffer grows unbounded.

## Start

```bash
python -m src.runtimes.log_buffer_cleanup.main
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | required | PostgreSQL DSN |
| `AURELION_LOG_BUFFER_RETENTION_DAYS` | `7` | Rows older than this are deleted on each sweep |
| `AURELION_LOG_BUFFER_CLEANUP_INTERVAL_SECONDS` | `3600` | How often the sweep runs (default: hourly) |

## Behavior

On each sweep the runtime issues a single `DELETE FROM log_buffer WHERE created_at < now() - interval '<retention_days> days'`. The operation is a best-effort sweep — if it fails, it logs the error and waits for the next interval. It does not retry within the same interval.

## Deployment

Run as a singleton. Running multiple replicas is safe (the DELETE is idempotent) but wasteful.
