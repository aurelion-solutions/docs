# Reconciliation

Reconciliation answers one question: *what changed in access for this Application since the last sync?*

## The idea

Think of two sets:

- **What should exist** — the access facts that follow from the current active artifacts
- **What exists now** — the active AccessFact rows in Inventory for this Application

Reconciliation is a set-diff between them:

```
Should exist: {A, B, C, D}
Exists now:   {B, C, E}

→ Create: A, D
→ Keep:   B, C  (if fields have not drifted)
→ Revoke: E
```

This is applied for one Application per run.

## How it works

**Step 1. Load artifacts.** All active AccessArtifact rows for the Application are fetched from the database.

**Step 2. Dispatch by type.** Each artifact is sent to the Handler registered for its `artifact_type`. The handler turns the raw payload into a list of `NormalizationResult` values — normalized candidates for access facts. An unknown `artifact_type` means the artifact is skipped, not errored.

**Step 3. Load current state.** All active AccessFact rows with `is_active = true` belonging to this Application are loaded for comparison.

**Step 4. Set-diff.** On the natural key `(subject_id, account_id, resource_id, action_id)`:

- New keys → `create_fact`
- Common keys with field drift → `refresh_fact_fields`
- Disappeared keys → `revoke_fact`

**Step 5. Emit result.** One event per run: `reconciliation.run.completed` with counters.

## Handlers

Handlers are pluggable components, one per `artifact_type`. They implement a single method: receive an artifact, return a list of candidates.

Built-in handlers:

| `artifact_type` | What it models |
|---|---|
| `role` | Generic role grant — one result per artifact |
| `sap_role` | SAP role/tcode grant, typically `action_slug=use` |
| `acl_entry` | NT/POSIX ACE — supports `allow` and `deny` effects |
| `db_grant` | SQL privileges (`SELECT`→`read`, `INSERT/UPDATE/DELETE`→`write`, `EXECUTE`→`execute`, `ADMIN OPTION`→`admin`); N results per artifact, deduplicated |
| `privilege` | Generic privilege — identical to `role` today, kept separate for future SoD divergence |

A new artifact type means a new handler file, no changes to the engine.

A handler must:
- Be stateless
- Not flush or commit
- Not emit events
- Resolve resources via `ResourceService.ensure_resource_by_identity` — return a `resource_id`, not a raw `resource_key`

A handler failure does not stop the whole run — the artifact is counted in `facts_errored` and processing continues.

## Transaction ownership

The reconciliation engine does not commit. That is the caller's responsibility: the REST route commits on success, the CLI goes through the API.

## Where it lives

`src/capabilities/reconciliation/` — the Capabilities layer. The engine adds no migrations and owns no ORM models. It uses Inventory services.

To run: `POST /api/v0/reconciliation/runs` or `al reconciliation run`.
