# API Overview

The Aurelion REST API is served by the `platform_api` runtime (FastAPI/uvicorn) on port `8000` by default.

## Base URL and versioning

All endpoints are under `/api/v0/`. There is no content negotiation — the version is in the path.

```
http://localhost:8000/api/v0/employees
```

The `VITE_API_BASE_URL` environment variable (no trailing slash) configures the base URL for the GUI. The CLI uses `AURELION_API_URL` or the `--base-url` flag.

## Request format

All write requests use `Content-Type: application/json`. Requests without a body (GET, DELETE) do not need a Content-Type header.

PATCH requests use partial update semantics: only fields present in the body are changed. Sending `null` for a field means "leave unchanged", not "clear".

## Response format

Successful responses return JSON. HTTP 204 responses have no body.

## Error responses

All errors return a JSON body:

```json
{
  "detail": "Employee not found"
}
```

For validation errors (422), `detail` is an array of field-level errors:

```json
{
  "detail": [
    {
      "loc": ["body", "code"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

## Common status codes

| Code | Meaning |
|---|---|
| 200 | Success (GET, PATCH) |
| 201 | Created (POST) |
| 204 | Deleted (DELETE) |
| 400 | Bad request (malformed input) |
| 404 | Resource not found |
| 409 | Conflict (duplicate unique key) |
| 422 | Validation failure (missing or invalid field) |
| 501 | Feature not implemented (e.g. log provider has no read support) |
| 503 | Service unavailable (e.g. no connector instance available) |

## Pagination

List endpoints do not use cursor or page-based pagination at the API level. Some endpoints accept a `limit` query parameter. If no limit is documented, the endpoint returns all matching records.

## Correlation ID header

Every request and response carries an `X-Correlation-ID` header.

| Direction | Behavior |
|---|---|
| Request (caller → kernel) | Optional. If present, the kernel uses the value as-is. If absent, the kernel generates a UUID for the request. |
| Response (kernel → caller) | Always present. Echoes the request value, or returns the generated UUID. |

The kernel never rejects a request for a missing or malformed header — generation is unconditional. Callers that drive multi-step workflows across services (CLI, Engineering Studio, aurelion-lens) should set the header themselves so events and logs from all services join on the same ID.

The same value appears as `correlation_id` on every `EventEnvelope` and log record emitted while handling the request. See [Correlation ID](../concepts/events.md#correlation-id) in concepts.

## Authentication

Authentication is not implemented in the current version. The API is intended to run within a trusted network boundary. Do not expose it directly to the public internet.

## Interactive docs

FastAPI generates interactive API documentation automatically:

- **Swagger UI**: `http://localhost:8000/docs`
- **ReDoc**: `http://localhost:8000/redoc`
- **OpenAPI schema**: `http://localhost:8000/openapi.json`
