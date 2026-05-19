# Access Plan Operations

Runbook for operating the declarative access-plan subsystem: creating plans,
triggering apply, reading status, and diagnosing stuck runs.

For the conceptual overview see the
[Declarative Access Planning concept](../concepts/access-planning.md).
For the full API contract see
[Access Plan API (reference)](../reference/access-plan-api.md).

---

## What is an access plan?

An access plan is an immutable, versioned record of **what access a subject
should have** and **what operations are needed to reach that state** from the
current effective access.

The engine follows three steps every time it builds a plan:

1. **Read current state** — `access_effective` returns the live access facts
   for the subject.
2. **Compute desired state** — `policy_assessment.generative` applies the
   tenant's policy rules to the subject's context and returns a list of
   projected access facts.
3. **Diff and order** — `access_plan` diffs desired versus current, resolves
   the concrete operation kinds (`account_create`, `grant_role`, etc.) from
   connector metadata, and builds a dependency DAG.

Nothing is provisioned until `POST /plans/{id}/apply` is explicitly called.
The plan is a plan, not an execution.

---

## Plan lifecycle

### Status values

| Status | Meaning |
|---|---|
| `active` | The plan is current and can be applied. |
| `superseded` | A newer plan for the same subject was created. This plan's diff is stale. |
| `cancelled` | Set when an operator cancels the plan through an operator UI. The kernel engine itself does not set this status. |
| `invalid` | The plan was invalidated automatically. See `invalidation_reason`. |

### Invalidation reasons

| `invalidation_reason` | When it is set |
|---|---|
| `structural` | A permanent structural condition makes this plan inapplicable (e.g. the target connector was deregistered). |
| `stale_after_apply` | Another plan for the same subject was applied after this plan was built. The diff this plan was based on is now out of date. |

`invalidation_reason` is `null` for `active` and `superseded` plans.

`invalidated_by_plan_id` is set (to the plan that triggered invalidation)
only when `invalidation_reason = stale_after_apply`. It is `null` otherwise.

### Supersedes chain

Each new plan for a subject points `supersedes_plan_id` at the prior
`active` plan for that subject. The chain lets you trace the planning history
backward.

---

## Creating a plan

### Via REST

```bash
curl -X POST http://localhost:8000/api/v0/plans \
  -H "Content-Type: application/json" \
  -d '{
    "subject_ref": "<subject_uuid>",
    "subject_type": "employee"
  }'
```

A `201 Created` response means a new plan was persisted. A `200 OK` response
means the request was deduplicated against an existing `active` plan with the
same `content_hash` within the 5-second deduplication window, or against a
plan with a matching `idempotency_key`.

Use `idempotency_key` when you want deterministic reuse across requests:

```json
{
  "subject_ref": "<subject_uuid>",
  "subject_type": "employee",
  "idempotency_key": "onboarding-2026-01-15-jdoe"
}
```

### Via dry-run (what-if)

`POST /plans/dry-run` runs the full diff and DAG computation but does **not**
persist anything. The response body contains the complete plan shape — items,
dependencies, `requires_confirmation` flag, and PDP decision snapshots.

Use dry-run for:

- Admin debugging via Engineering Studio.
- UI previews before committing to an apply.
- Checking whether a context change would produce destructive operations.

```bash
curl -X POST http://localhost:8000/api/v0/plans/dry-run \
  -H "Content-Type: application/json" \
  -d '{"subject_ref": "<uuid>", "subject_type": "employee"}'
```

---

## Applying a plan

```bash
curl -X POST http://localhost:8000/api/v0/plans/<plan_id>/apply
```

The endpoint returns a `pipeline_run_id`. The actual execution runs
asynchronously in the executor process. Poll `GET /plans/<plan_id>` or
`GET /api/v0/pipeline-runs/<pipeline_run_id>` to track progress.

### Destructive threshold (`requires_confirmation`)

If the plan contains more revoke operations than the configured threshold
(default 50 % of all items), `requires_confirmation` is set to `true` on
the plan. Calling `POST /plans/{id}/apply` without the confirmation flag
returns:

```
422 Unprocessable Entity
{"detail": "Plan requires confirmation for destructive operations",
 "code": "destructive_threshold_exceeded"}
```

To proceed, pass `?confirm_destructive=true`:

```bash
curl -X POST \
  "http://localhost:8000/api/v0/plans/<plan_id>/apply?confirm_destructive=true"
```

### Non-active plans

Attempting to apply a `superseded`, `invalid`, or `cancelled` plan returns
`409 Conflict` with `code: plan_not_active`. The response body includes
`invalidation_reason` when set.

---

## Reading plan status

### GET /plans/{id}

Returns the full plan record including all `PlanItem` rows and their current
`PlanItemExecution` status.

| Field | Meaning |
|---|---|
| `status` | Plan-level lifecycle status (`active`, `superseded`, `invalid`, `cancelled`). |
| `invalidation_reason` | `structural`, `stale_after_apply`, or `null`. |
| `invalidated_by_plan_id` | UUID of the plan that caused `stale_after_apply`; `null` otherwise. |
| `requires_confirmation` | `true` if the plan needs `?confirm_destructive=true` before apply. |
| `supersedes_plan_id` | UUID of the plan this one replaced; `null` for first plan for a subject. |
| `items[].execution.status` | Per-item status: `proposed`, `executing`, `done`, `failed`. |
| `items[].execution.failure_reason` | `precondition`, `apply_error`, `verify_mismatch`, `verify_timeout`, or `null`. |

---

## Scheduled background scans

Two pipelines run continuously to keep the planning subsystem honest.

### `initiatives_scheduled_replan_scan` (cron 1 m)

Walks `initiatives` for rows whose `valid_from` or `valid_until` boundary
crossed `now()` since the last tick. For each affected subject, the scanner
emits `subject.scheduled_replan_required` on `aurelion.events`. The replan
matcher consumes that event and creates a fresh plan.

This is what closes the loop on "Иван's grace ends at 2026-06-01 09:00" —
no upstream event needs to fire; the scanner does.

The pipeline definition lives at
`aurelion-kernel/pipelines/initiatives_scheduled_replan_scan.yaml`.

### `access_apply_active_cleanup_scan` (cron 1 m)

Sweeps `access_apply_active` rows whose `pipeline_run_id` reached a terminal
status, releasing leases left behind by crashed workers (see below).

## Diagnosing a stuck apply lease

The `access_apply_active` table holds one row per subject currently undergoing
apply. A row is inserted when `POST /plans/{id}/apply` fires and deleted by
the executor's `finally` block when `execute_plan` completes.

If a worker crashes before the `finally` block runs, the row can remain
indefinitely. Two automatic cleanup paths handle this:

1. **`access_apply_active_cleanup_scan` pipeline** (cron 1 m): reads each
   `access_apply_active` row, looks up the referenced `pipeline_run`, and
   deletes the row if the run is in a terminal state (`completed`, `failed`,
   or `cancelled`).
2. **Defensive read in the endpoint**: when `POST /plans/{id}/apply` gets a
   409 conflict, it reads the existing row's `pipeline_run_id`. If that run
   is already terminal, it deletes the stale row and retries the insert —
   without waiting for the scanner.

### Manual diagnosis

```bash
# List all active apply leases
curl http://localhost:8000/api/v0/plans/apply-leases

# Check the pipeline run referenced by a lease
curl http://localhost:8000/api/v0/pipeline-runs/<pipeline_run_id>
```

If `pipeline_run.status` is `failed` or `cancelled` but the lease row still
exists (rare — scanner tick may be pending), you can safely delete the lease
by re-issuing `POST /plans/{id}/apply`. The defensive read in the endpoint
handles cleanup automatically.

---

## Diagnosing a stuck plan execution

### Step 1 — Check plan status

```bash
curl http://localhost:8000/api/v0/plans/<plan_id>
```

Look for items with `execution.status = failed` and check `failure_reason`.

| `failure_reason` | Meaning |
|---|---|
| `precondition` | A dependency item has not completed. Check the failed dependency item first. |
| `apply_error` | The connector call returned an error. Check `last_error` on the item and connector logs. |
| `verify_mismatch` | The post-apply verification found the target system in an unexpected state. May require manual investigation of the target system. |
| `verify_timeout` | The verification call timed out (default 30 s). Check connector connectivity. |

### Step 2 — Check the pipeline run

```bash
curl http://localhost:8000/api/v0/pipeline-runs/<pipeline_run_id>
```

If the run is `failed`, inspect `step_runs` for the `access_apply.execute_plan`
step. The step's `error` field contains the last exception message.

### Step 3 — Retry

Failed runs are not auto-retried. To retry:

1. Confirm the plan is still `active` (if another plan was applied in the
   meantime, this plan will be `invalid`).
2. Re-issue `POST /plans/<plan_id>/apply`. The executor resumes from the last
   committed `PlanItemExecution` — items with `status = done` are skipped.

### Step 4 — Replan after invalidation

If the plan is `invalid` (e.g. `stale_after_apply`), create a fresh plan:

```bash
curl -X POST http://localhost:8000/api/v0/plans \
  -H "Content-Type: application/json" \
  -d '{"subject_ref": "<subject_uuid>", "subject_type": "employee"}'
```

The new plan is built on the current effective access state and supersedes
the stale one.

---

## Who runs this

Platform engineers and operators with API access to the kernel. This is not
an end-user-facing procedure — there is no admin UI for access plans.
