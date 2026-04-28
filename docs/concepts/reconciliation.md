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

**Step 5. Emit result.** A run emits a sequence of events on `aurelion.events`: `reconciliation.run.started`, `reconciliation.delta.created`, and either `reconciliation.run.completed` (success) or `reconciliation.run.failed` (failure). See [Events and Logs](events.md#reconciliation-event-ordering) for ordering semantics.

## Run modes

A run takes a `mode` parameter that controls what happens after the diff is materialised:

- `review` (default) — persist delta items, leave the run in `pending_apply`. Apply is a separate step (`POST /reconciliation/runs/{id}/apply`).
- `dry_run` — persist delta items, mark the run `dry_run_completed`. No apply will follow.
- `auto_apply` — persist delta items, then immediately delegate to `SyncApplyService` to write approved items to the `normalized.access_facts` Iceberg table. The same request handles both phases under the same advisory lock.

The diff itself is mode-agnostic. Mode only changes the terminal status and whether downstream apply runs as part of the same request.

## Apply

Reconciliation only stages a diff. Writing the resulting facts to the lake — and emitting `inventory.access_fact.*` events — is owned by `SyncApplyService` in `capabilities/sync_apply/`. This split is intentional:

- Reconciliation must not depend on apply-side semantics. The reconciliation slice is forbidden by an architecture invariant from importing `SyncApplyService`, `lake_writer`, or `preflight_recover_already_written` — except in `routes.py`, which is the single allowed bridge for `auto_apply`.
- Apply owns the mandatory `preflight_recover_already_written` step that runs on every attempt before any new Iceberg write, so a crashed previous run never produces duplicate facts.
- Apply is the sole emitter of `inventory.access_fact.{created,updated,revoked,reactivated}`; `AccessFactService` mutating methods do not emit these events.

See [Reconciliation reference / Apply runs](../reference/reconciliation.md#apply-runs) for the API surface.

## Concurrency

Only one run per application can be in flight at a time. The kernel takes a Postgres advisory lock keyed by `application_id` for the duration of the run; a concurrent attempt for the same application is rejected with `409 Conflict` rather than serialised. Different applications run in parallel.

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
