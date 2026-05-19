# Access Apply

`access_apply` is the egress engine that applies planned access changes to external systems. It is the executor for declarative `AccessPlan`s — for the end-to-end flow see [Declarative Access Planning](../concepts/access-planning.md).

The engine exposes two surfaces: the plan-driven executor (the canonical IGA path) and a direct fire-and-forget account create/delete API for connectors that are not descriptor-driven.

## Plan-driven execution (canonical)

`execute_plan(plan_id)` is the runtime path used by `POST /api/v0/plans/{plan_id}/apply`. The executor:

1. Acquires the per-subject `access_apply_active` lease.
2. Walks the plan's DAG in dependency order.
3. For each item:
   - Calls `verify_fact` (preflight) when the connector declares `verify_fact_supported: true` to detect "already done" states.
   - Invokes the connector with the operation.
   - Calls `verify_fact` (post-apply) to confirm the change.
   - Calls `inventory_sync.sync_single_fact(descriptor, op, event_key)` to persist the resulting fact into `normalized.access_facts`.
4. Releases the lease in a `finally` block.

Wire-level idempotency comes from `event_key = hash(plan_item_id, op)`, stored as a column on `normalized.access_facts`.

For the full operational runbook (creating, applying, diagnosing plans), see [Access Plan Operations](../operations/access-plan.md). The REST contract for `/plans/...` lives in [Access Plan API](access-plan-api.md).

## Direct provisioning API

For connectors that are not wired into the descriptor-driven flow, the platform exposes a fire-and-forget surface. The command is enqueued over RabbitMQ and the call returns immediately; results come back asynchronously via [Connector Results](connector-results.md).

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

The direct surface is API-only. Use `curl` or an SDK client.

```bash
# Create
curl -X POST http://localhost:8000/api/v0/applications/<id>/accounts \
  -H "Content-Type: application/json" \
  -d '{"username": "jdoe", "email": "jdoe@example.com"}'

# Delete
curl -X DELETE http://localhost:8000/api/v0/applications/<id>/accounts/jdoe
```

Target the plan-driven flow whenever possible — it gives you DAG ordering, verify_fact protection, idempotency, and a single audit trail. The direct API exists only for connectors that cannot yet supply a descriptor.
