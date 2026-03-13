# Provisioning

Sends account create and delete commands to a connector for a specific application. Provisioning is a fire-and-forward operation — the platform enqueues the command over RabbitMQ and returns immediately. Results are reported back asynchronously via [Connector Results](connector-results.md).

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/applications/{id}/accounts` | Create an account in the application |
| `DELETE` | `/api/v0/applications/{id}/accounts/{username}` | Delete an account in the application |

### Create account — request body

```json
{
  "username": "jdoe",
  "email": "jdoe@example.com"
}
```

**201 Created** — account creation command dispatched.

### Delete account

**204 No Content** — account deletion command dispatched.

### Errors

| Code | Condition |
|---|---|
| 404 | Application not found |
| 422 | Validation failure |
| 503 | No connector instance available for the application's tags |

## No CLI equivalent

Provisioning is API-only. Use `curl` or an SDK client.

```bash
# Create
curl -X POST http://localhost:8000/api/v0/applications/<id>/accounts \
  -H "Content-Type: application/json" \
  -d '{"username": "jdoe", "email": "jdoe@example.com"}'

# Delete
curl -X DELETE http://localhost:8000/api/v0/applications/<id>/accounts/jdoe
```
