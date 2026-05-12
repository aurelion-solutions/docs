# Reconciliation

Reconciliation answers one question: *what changed in this Application since the last sync?*

Two engines split the responsibility:

- **`inventory_reconcile`** stages the diff: it computes what created, updated, or revoked rows would be needed and persists them as `delta_items`.
- **`inventory_sync`** applies the diff: it writes approved deltas into the `normalized.access_facts` Iceberg table.

The split is intentional — staging is reversible, applying is not.

> Renamed in Phase 19 (A2–A4): `reconciliation → inventory_reconcile`, `sync_apply → inventory_sync`. The URL path also moved to `/api/v0/inventory-reconciles`. The previous `/reconciliation/...` paths are gone.

## The idea

Think of two sets:

- **What should exist** — the rows that follow from the latest raw snapshot.
- **What exists now** — the active rows in Inventory for this Application.

Reconciliation is a set-diff between them:

```
Should exist: {A, B, C, D}
Exists now:   {B, C, E}

→ Create: A, D
→ Keep:   B, C  (if fields have not drifted)
→ Revoke: E
```

This applies for one Application per run.

## Two entity types

A reconciliation run is parameterised by `entity_type`. Phase 19 added `account` alongside `access_fact`:

| `entity_type` | What it diffs | Delta target |
|---|---|---|
| `access_fact` | Effective access grants per `(subject, account, resource, action)` | `normalized.access_facts` (Iceberg) |
| `account` | Account rows per `(application_id, username)` | `accounts` Postgres table |

Both share the same run-state machine and the same delta-item table — only the handler and the apply target differ.

## How it works

**Step 1. Read raw snapshot from the lake.** All Iceberg-backed raw tables are queried by snapshot id, not by per-row reads. The pipeline streams rows in `fetchmany` batches (controlled by `reconciliation_fetch_batch_size`).

**Step 2. Dispatch by handler.** Each handler turns lake rows into normalized candidates:

- `access_fact` runs the artifact-type-specific handlers (`role`, `acl_entry`, `db_grant`, …) over `raw.access_artifacts`.
- `account` runs `AccountHandler.compute_delta` over `raw.accounts` (introduced in Phase 19 H9–H10).

**Step 3. Load current state.** Live Inventory rows are loaded for comparison. For `access_fact` this means active `AccessFact` rows in `normalized.access_facts`; for `account` it means rows in the `accounts` Postgres table.

**Step 4. Set-diff.** The handler produces five operations: `create`, `update`, `revoke`, `reactivate`, `noop`.

**Step 5. Emit result.** A run emits a sequence of events on `aurelion.events`: `reconciliation.run.started`, `reconciliation.delta.created`, and either `reconciliation.run.completed` (success) or `reconciliation.run.failed` (failure). See [Events and Logs](events.md#reconciliation-event-ordering) for ordering semantics.

## Lake-first for master data

Phase 19 H10 unified the path for all five master-data entities — `persons`, `employees`, `org_units`, `access_artifacts`, and `accounts`. Bulk endpoints write raw rows directly to an Iceberg table (`raw.<entity>`) and return a `{row_count, snapshot_id}` envelope; reconciliation runs read that lake snapshot, diff against Postgres, and persist delta items. The previous PG-direct upsert paths for accounts were removed.

The shape:

```
                connector / bulk POST
                          │
                          ▼
                    raw.<entity> (Iceberg snapshot)
                          │
                          ▼
              inventory_reconcile run
                          │
                          ├──→  delta_items
                          ▼
              inventory_sync apply
                          │
                          ▼
        normalized.access_facts  /  accounts (PG)
```

This shape means a connector can publish a snapshot, walk away, and never need to coordinate with the kernel for the diff to be picked up later.

## Run modes

A run takes a `mode` parameter that controls what happens after the diff is materialised:

- `review` (default) — persist delta items, leave the run in `pending_apply`. Apply is a separate step (`POST /inventory-reconciles/runs/{id}/apply`).
- `dry_run` — persist delta items, mark the run `dry_run_completed`. No apply will follow.
- `auto_apply` — persist delta items, then immediately delegate to `inventory_sync` to write the result. The same request handles both phases under the same advisory lock.

The diff itself is mode-agnostic. Mode only changes the terminal status and whether downstream apply runs as part of the same request.

## Apply

Reconciliation only stages a diff. Writing the resulting rows — and emitting `inventory.access_fact.*` or `inventory.account.*` events — is owned by `inventory_sync`. This split is intentional:

- `inventory_reconcile` must not depend on apply-side semantics. The slice is forbidden by an architecture invariant from importing `inventory_sync` symbols except in `routes.py`, which is the single allowed bridge for `auto_apply`.
- Apply owns the mandatory `preflight_recover_already_written` step that runs on every attempt before any new Iceberg write, so a crashed previous run never produces duplicate rows.
- Apply is the sole emitter of the per-row inventory events.

`inventory_sync` exposes a narrow `sync_single_fact(descriptor, op, event_key)` API used by the declarative-planning path (see [Access Planning](access-planning.md)). Wire-level idempotency is provided by `event_key = hash(plan_item_id, op)`, stored as a column on `normalized.access_facts`.

See [Reconciliation reference / Apply runs](../reference/reconciliation.md#apply-runs) for the API surface.

## Concurrency

Only one run per `(application_id, entity_type)` can be in flight at a time. The kernel takes a Postgres advisory lock keyed on that pair for the duration of the run; a concurrent attempt is rejected with `409 Conflict` rather than serialised. Different applications run in parallel, as do `account` and `access_fact` runs for the same application.

## Handlers

The dispatch step is pluggable: one handler per `artifact_type` for `access_fact` runs, plus `AccountHandler` for `account` runs. Each handler is stateless — it receives raw rows and returns a list of normalized candidates. New connectors usually mean a new handler, not a change to the engine.

For the catalog of built-in handlers and the handler contract, see [Reconciliation reference — Handlers](../reference/reconciliation.md#handlers).

## Transaction ownership

The reconciliation engine does not commit. That is the caller's responsibility: the REST route commits on success, the CLI goes through the API.

## Where it lives

`src/engines/inventory_reconcile/` and `src/engines/inventory_sync/` — Engines layer. Neither engine adds migrations or owns ORM models; they use Inventory services.

To run: `POST /api/v0/inventory-reconciles/runs` or `al inventory-reconcile run`.
