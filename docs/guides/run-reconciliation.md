# How to run reconciliation

Reconciliation compares the current active access artifacts for an application against the active access facts in Inventory, then creates, updates, or revokes facts to bring the two in sync.

## Prerequisites

- An application registered in Aurelion — see [Connect an application](connect-application.md)
- At least one active `AccessArtifact` for that application (ingested via a connector)
- A connector instance online and resolvable for the application

## Run via CLI

```bash
al reconciliation run --application-id <application-uuid>
```

Example:
```bash
al reconciliation run --application-id 550e8400-e29b-41d4-a716-446655440000
```

## Run via API

```bash
curl -X POST http://localhost:8000/api/v0/reconciliation/runs \
  -H "Content-Type: application/json" \
  -d '{"application_id": "550e8400-e29b-41d4-a716-446655440000"}'
```

## Reading the result

A successful run returns a summary:

```
Reconciliation completed for application 550e8400-e29b-41d4-a716-446655440000
  artifacts_ingested:  42
  facts_created:       5
  facts_updated:       2
  facts_revoked:       1
  artifacts_unhandled: 0
```

| Counter | What it means |
|---|---|
| `artifacts_ingested` | How many active artifacts the engine loaded |
| `facts_created` | New access facts written (subjects gained access) |
| `facts_updated` | Existing facts updated due to field drift (effect, validity dates) |
| `facts_revoked` | Facts revoked because the artifact no longer describes that access |
| `artifacts_unhandled` | Artifacts whose `artifact_type` has no registered handler — they are skipped, not errored |

## Diagnosing problems

**`artifacts_ingested: 0`** — No active artifacts exist for this application. Check that your connector has pushed data via `POST /api/v0/connector-results`.

**`artifacts_unhandled > 0`** — One or more artifact types have no registered handler. The engine skips them silently. Check the `artifact_type` values on your artifacts and verify the handler is registered.

**`facts_revoked` is very large** — The run emits a `WARNING`-level event when `facts_revoked > 100`. This usually means a large batch of access was removed at the source. Investigate whether this is expected or if the connector sent incomplete data.

**Per-artifact errors** — Handler exceptions and unknown `action_slug` values are counted internally as `facts_errored`. They do not cause the run to fail and are not printed by the CLI, but they appear as `WARNING` log lines on the server tagged `component=capabilities.reconciliation`.

## What happens after a run

The engine emits a `reconciliation.run.completed` event on `aurelion.events`. Downstream projections (the Effective Access Store) pick this up and update their read models. Individual fact-level events (`inventory.access_fact.created`, `.updated`, `.revoked`) are emitted by the Inventory services during the run.

## Automation

Reconciliation does not run on a schedule automatically — you trigger it. For continuous sync, call the endpoint from your orchestration layer (cron, workflow engine, connector post-push hook) after each data push from the connector.
