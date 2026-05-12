# Access Apply

`access_apply` is the egress engine that applies planned access changes to external systems. In Phase 19 it became the executor for declarative `AccessPlan`s — for the end-to-end flow see [Declarative Access Planning](../concepts/access-planning.md).

> Phase 19 renamed `provisioning → access_apply`. The legacy "fire-and-forget account create/delete" surface described below remains for connectors that have not yet wired into the descriptor-driven plan executor.

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

Wire-level idempotency comes from `event_key = hash(plan_item_id, op)`, which is stored as a column on `normalized.access_facts` (Phase 19 B1 added the column via `ALTER TABLE`).

For the full operational runbook (creating, applying, diagnosing plans), see [Access Plan Operations](../operations/access-plan.md). The REST contract for `/plans/...` lives in [Access Plan API](access-plan-api.md).

## Legacy direct provisioning API

For backward compatibility, the platform still exposes a fire-and-forget surface for connectors that have not been wired into the descriptor-driven flow. The command is enqueued over RabbitMQ and the call returns immediately; results come back asynchronously via [Connector Results](connector-results.md).

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

The legacy surface is API-only. Use `curl` or an SDK client.

```bash
# Create
curl -X POST http://localhost:8000/api/v0/applications/<id>/accounts \
  -H "Content-Type: application/json" \
  -d '{"username": "jdoe", "email": "jdoe@example.com"}'

# Delete
curl -X DELETE http://localhost:8000/api/v0/applications/<id>/accounts/jdoe
```

For new integrations target the plan-driven flow — it gives you DAG ordering, verify_fact protection, idempotency, and a single audit trail.
