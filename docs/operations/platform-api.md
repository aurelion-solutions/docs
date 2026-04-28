# Platform API Runtime

The main HTTP API server. All REST endpoints, the FastAPI application, and the database connection pool live here.

## Start

From `aurelion-kernel/`:

```bash
uv run uvicorn src.runtimes.platform_api.main:app \
  --host 0.0.0.0 \
  --port 8000 \
  --reload          # dev only
  --log-level debug # dev only
  --access-log      # dev only
```

In production, drop `--reload` and `--log-level debug`. Use a process supervisor (systemd, Docker, etc.) to manage the process lifecycle.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | required | PostgreSQL async DSN (`postgresql+asyncpg://...`) |
| `AURELION_RABBITMQ_HOST` | `localhost` | RabbitMQ host |
| `AURELION_RABBITMQ_PORT` | `5672` | RabbitMQ port |
| `AURELION_RABBITMQ_USERNAME` | — | Optional; falls back to `guest` |
| `AURELION_RABBITMQ_PASSWORD` | — | Optional; pairs with username |
| `LAKE_CATALOG_URL` | kernel PG `iceberg_catalog` schema | PyIceberg SQL catalog URL (SQLAlchemy form). |
| `LAKE_CATALOG_NAME` | `aurelion` | Logical PyIceberg catalog name. |
| `LAKE_WAREHOUSE_URI` | `file:///var/lib/aurelion/warehouse` | Warehouse storage root. Use `file://` in dev, `s3://` in prod. Must be writable by the runtime user. |
| `LAKE_STORAGE_PROVIDER` | `file` | One of `file`, `s3`. |
| `LAKE_POOL_SIZE` | `4` | DuckDB session pool capacity. |
| `LAKE_ACQUIRE_TIMEOUT_SECONDS` | `5.0` | Pool acquisition timeout before `LakePoolExhaustedError`. |
| `LAKE_ARTIFACTS_WRITE_BACKEND` | `pg` | Migration gate for `access_artifacts`. `pg` keeps the SQLAlchemy write path and offset-paginated reads; `iceberg` routes writes through PyIceberg and reads through DuckDB `iceberg_scan` with cursor pagination. **Production should stay on `pg` for now** — the `iceberg` path is wired and tested but not yet exercised at production scale. |
| `LAKE_READ_PAGE_SIZE` | `1000` | Default page size for cursor-paginated lake reads (`GET /access-artifacts` under the `iceberg` backend). Maximum 5000. |

See `aurelion-kernel/.env.example` for the full list.

### Switching the artifacts backend

`LAKE_ARTIFACTS_WRITE_BACKEND` is a one-way migration gate, not a hot toggle. Flipping it does not move existing data — rows written under `pg` stay in PostgreSQL, rows written under `iceberg` stay in the lake. Run the [lake migration runbook](lake-migration-runbook.md) (one-shot PG → Iceberg backfill of `access_artifacts` and `access_facts`) before flipping the gate. Flipping back to `pg` after writes have landed in Iceberg leaves the lake-resident rows invisible to the API and re-routes new writes to PG — split-brain. If you need to roll back, restore from the pre-flip backup.

## Startup dependencies

On startup the runtime initializes the lake infrastructure in addition to the database and message queue:

- Resolves `LakeSettings` from environment.
- Loads the PyIceberg SQL catalog backed by the PG schema `iceberg_catalog`. The schema must exist before the API starts — run `uv run alembic upgrade head` after each deployment.
- Provisions the Iceberg tables `raw.access_artifacts` and `normalized.access_facts` idempotently. Existing tables are left untouched; schema drift against the declared schemas is logged as a warning but not auto-migrated.
- Constructs the DuckDB session pool. `LAKE_WAREHOUSE_URI` must point to a writable location.

If any of these fail, lifespan aborts and the process exits. Check kernel logs for `platform.lake.catalog_init_failed`, `platform.lake.tables_ensure_failed`, or `platform.lake.session_bootstrap_failed`. A `platform.lake.table_schema_drift_detected` warning means an existing table's schema diverges from the declared constants — investigate before the next deploy, schema evolution is handled by explicit migrations only.

## Middleware

The runtime installs a correlation-ID middleware in front of the application. For every request it reads `X-Correlation-ID` (or generates a UUID if absent), stores the value in a per-request `ContextVar`, and echoes it back on the response. Domain events and log records emitted while handling the request inherit that ID automatically. See the [API correlation ID contract](../api/overview.md#correlation-id-header) and [Correlation ID concepts](../concepts/events.md#correlation-id).

## Health

The process is healthy when it accepts HTTP connections on the configured port. There is no dedicated `/health` endpoint — use a TCP check or `GET /docs` (200 = alive).

## Interactive API docs

| URL | Description |
|---|---|
| `/docs` | Swagger UI |
| `/redoc` | ReDoc |
| `/openapi.json` | OpenAPI schema |

## Scaling

The API is stateless — all state lives in PostgreSQL and RabbitMQ. Multiple replicas behind a load balancer are safe. Database connection pool size is the primary scaling constraint.
