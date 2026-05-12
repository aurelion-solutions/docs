# Declarative Access Planning

Phase 19 shifted Aurelion from a reactive JML/lifecycle model to **declarative, continuous reconciliation** of access. Instead of mutating access in response to events ("employee joined → grant role X"), the kernel continuously computes the desired state from policy and reduces the live state toward it.

The shape:

```
   subject_context, current_facts, current_initiatives
                            │
                            ▼
         policy_assessment.generative   ──→  desired ProjectedFacts
                            │
                            ▼
              access_plan (diff + DAG)  ──→  AccessPlan { items, dependencies }
                            │
                            ▼
              access_apply.execute_plan
                            │
                            ▼
            connector ops with verify_fact per step
```

Subject can be either `employee` or `nhi`.

## Why declarative

Reactive J/M/L flows have three operational properties that bite at scale:

- They are **fragile under retries** — an event missed or processed twice can leave access in a wrong state forever, because there is no canonical source of truth to compare against.
- They **couple every grant to the trigger that produced it** — answering "why does Иван still have admin in Slack?" requires walking an event history that may not exist.
- They **silently drift** when policy rules change — existing access is not retroactively corrected unless someone runs a manual remediation.

Declarative planning fixes all three by making "what access should this subject have right now" the canonical question. The kernel can recompute that answer at any time and produce a plan to bridge the gap.

## The three steps

### 1. PDP.generative — compute desired state

`policy_assessment.generative` is a stateless engine method introduced in Phase 19:

```
(subject_ref, subject_type, subject_context,
 current_facts, current_initiatives) -> list[ProjectedFact]
```

It returns a list of `ProjectedFact`s — what facts the subject should hold, given current policy and context. Each fact carries a `Decision` with `actions`, `signals`, and `reasons` for traceability.

The method is pure: same inputs produce the same outputs. No DB writes, no events, no side effects. This is what makes the planning idempotent and dry-runnable.

The output is "desired state at this moment given this policy". It is not a plan — turning it into operations is the next step.

### 2. access_plan — diff + DAG

The `access_plan` engine reads the current effective access (via `access_effective`) and the desired state (via PDP.generative), computes the diff, resolves each diff entry to a concrete operation kind from the connector descriptor, and orders the resulting `PlanItem`s into a DAG.

The resolver consults the connector descriptor's `account_status.transitions` graph to translate "this subject needs an active account in App X" into a concrete `account_create` or `account_activate` (or both, in sequence). Dependencies declared in `operations[].dependency_rules` become DAG edges. Cascades from `cascades:` synthesize prerequisite revoke/remove items before a destructive op.

The plan is **immutable** once persisted. New plans for the same subject `supersede` the previous active plan via `supersedes_plan_id`. Earlier plans don't disappear — they enter `superseded` status and stick around for audit.

If the diff is dominated by destructive operations (more than the configured threshold, default 50 % revokes), the plan is flagged with `requires_confirmation = true` and `POST /plans/{id}/apply` requires `?confirm_destructive=true`.

### 3. access_apply.execute_plan — execute with verify_fact

The plan executes asynchronously inside a pipeline run. For each item, in DAG order:

1. **Preflight verify** — if the connector declares `verify_fact_supported: true`, `access_apply` asks "does this fact already exist?" before invoking. If yes, the item completes as `done` without an apply call (idempotency / external race protection).
2. **Apply** — invoke the connector with the operation.
3. **Post-apply verify** — read back from the connector and confirm the change. A mismatch sets `failure_reason = verify_mismatch`; a timeout sets `verify_timeout` (default 30 s).

Each successful apply calls `inventory_sync.sync_single_fact(descriptor, op, event_key)` to write the resulting fact into the lake. `event_key = hash(plan_item_id, op)` gives wire-level idempotency — a retry produces the same key and the lake writer collapses duplicates.

The `access_apply_active` lease ensures only one apply per subject runs at a time. The lease is released by a `finally` block; orphan leases from crashes are swept by `access_apply_active_cleanup_scan` (cron 1m) and by a defensive read inside `POST /plans/{id}/apply` on `409`.

## Plan invalidation

Plans become stale in two ways:

| `invalidation_reason` | Cause |
|---|---|
| `structural` | A permanent structural change made the plan inapplicable — e.g. the target connector was decommissioned. |
| `stale_after_apply` | Another plan for the same subject was applied **after** this plan was built, so this plan's diff is no longer accurate. `invalidated_by_plan_id` points at the plan that triggered invalidation. |

Once `status = invalid`, the plan cannot be applied — `POST /plans/{id}/apply` returns `409` with `code: plan_not_active`. Create a fresh plan to replan against the current state.

## Triggers for replan

Phase 19 introduced an event-driven replan matcher that consumes events from `aurelion.events` and emits new plans automatically. The matcher fans out — a single trigger can produce multiple plans (e.g. `application.decommissioned` produces one plan per NHI in that application):

| Routing key | When replan fires |
|---|---|
| `subject.context.changed` | Employee changed department, NHI tags rotated, etc. |
| `subject.employment_status.changed` | Hire, terminate, transfer |
| `subject.scheduled_replan_required` | Future `valid_from` or `valid_until` boundary crossed |
| `initiative.changed` | Initiative validity edited (manual or PATCH) |
| `nhi.expired` | NHI passed its expiry |
| `application.decommissioned` | Fan-out: one plan per NHI in the app |

A separate scheduled scanner (`initiatives_scheduled_replan_scan`, cron 1m) catches future `valid_from` / `valid_until` boundaries and emits `subject.scheduled_replan_required` for affected subjects. This is what closes the loop on "Иван's grace period ends at 2026-06-01 09:00" — no upstream event needs to fire; the scanner does it.

## Initiatives as audit trail

Every access fact carries one or more `Initiative` rows in Phase 19, with a typed `origin` field:

| `type` | `origin` format | Used by |
|---|---|---|
| `birthright` | `policy_rule:<rule_id>` | PDP.generative re-derivation |
| `requested` | `request:<request_id>` | Trace back to the request that granted it |
| `delegated` | `delegation:<delegator_subject_ref>` | Trace back to the delegator |
| `grace` | `grace:<source_initiative_id>` | Identify grace periods following revocation |

When access is revoked, the matching initiative is **not deleted** — its `valid_until` is set to `now()`. This preserves the audit thread "who/what justified this access, and when did it end".

See [Initiative reference](../reference/initiatives.md) for the full type list and the API.

## The multi-transport action pattern

Phase 19 codified an architectural pattern that several engine actions now follow: business logic lives in `service.py` and is invoked through three transports:

1. **Pipeline action** — invoked by the orchestrator inside a pipeline step.
2. **REST endpoint** — invoked synchronously by an external caller.
3. **MQ matcher** — invoked asynchronously by an event subscription.

All three call the same service method with the same arguments; only the input parsing and the response shape differ. The benefit: behaviour is identical regardless of how the action was triggered, and the test surface is the service method, not three near-duplicates.

This is now an architectural invariant — adding a new transport (e.g. CLI) must not require a parallel implementation of the business logic.

## Where it lives

| Concern | Slice |
|---|---|
| Generative PDP method | `engines/policy_assessment/` |
| Diff + DAG | `engines/access_plan/` |
| Plan execution / verify_fact | `engines/access_apply/` |
| Lake write | `engines/inventory_sync/` (`sync_single_fact`) |
| Current state read | `engines/access_effective/` |
| Replan matcher | platform MQ subscription wiring |
| Scheduled scanner | `pipelines/initiatives_scheduled_replan_scan.yaml` |

## See also

- [Access Plan API (reference)](../reference/access-plan-api.md) — full request/response shapes for `/plans` and `/plans/items`.
- [Access Plan Operations (runbook)](../operations/access-plan.md) — how to create, apply, and diagnose plans in production.
- [Connector Descriptor (reference)](../reference/connector-descriptor.md) — the YAML shape that the DAG resolver consumes.
- [Reconciliation concept](reconciliation.md) — the batch-diff sibling that handles ingress; declarative planning handles egress against a desired state.
- [Access Analysis concept](access-analysis.md) — the older batch-analytics engine that still ships; see the note at the top of that page for how the two engines relate.
