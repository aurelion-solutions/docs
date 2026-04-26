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

See `aurelion-kernel/.env.example` for the full list.

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
