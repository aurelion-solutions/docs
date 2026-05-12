# Access Plan API

REST API reference for the `access_plan` engine.

For a how-to guide, see [Access Plan Operations](../operations/access-plan.md).

Base path: `/api/v0`

---

## Authorization

All endpoints inherit the kernel's standard bearer-token authentication.
Supply `Authorization: Bearer <token>` on every request. A missing or invalid
token returns `401`.

---

## Error shape

All error responses follow this schema:

```json
{
  "detail": "Human-readable message",
  "code": "machine_readable_code",
  "fields": ["optional", "list", "of", "field.paths"]
}
```

`fields` is present only for validation errors (`422`).

---

## POST /plans

Create a new access plan for a subject.

### Request body

```json
{
  "subject_ref": "550e8400-e29b-41d4-a716-446655440000",
  "subject_type": "employee",
  "idempotency_key": "optional-stable-key",
  "context_overrides": null
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `subject_ref` | UUID | yes | Subject's UUID in `inventory.subjects` |
| `subject_type` | `"employee"` \| `"nhi"` | yes | Determines which inventory source is read |
| `idempotency_key` | string | no | If an `active` plan with this key exists, it is returned as-is |
| `context_overrides` | object | no | Key-value overrides fed to `policy_assessment.generative`; used for what-if only in `dry-run` mode |

### Responses

| Code | Condition | Body |
|---|---|---|
| `201 Created` | New plan created | `AccessPlanRead` (see below) |
| `200 OK` | Deduplicated: request matched an existing `active` plan by `idempotency_key` or `content_hash` within the 5-second dedup window | `AccessPlanRead` |
| `404 Not Found` | `subject_ref` not found | error |
| `422 Unprocessable Entity` | Validation failure | error with `fields` |

### AccessPlanRead

```json
{
  "id": "uuid",
  "subject_ref": "uuid",
  "subject_type": "employee",
  "status": "active",
  "invalidation_reason": null,
  "invalidated_by_plan_id": null,
  "requires_confirmation": false,
  "supersedes_plan_id": null,
  "idempotency_key": null,
  "content_hash": "sha256hex",
  "created_at": "2026-01-15T10:00:00Z",
  "items": [
    {
      "id": "uuid",
      "kind": "account_create",
      "application": "uuid",
      "account_ref": null,
      "target_descriptor": {"application_id": "uuid", "username": "jdoe"},
      "initiatives": [
        {
          "type": "birthright",
          "origin": "policy_rule:rule-uuid",
          "valid_from": "2026-01-15T10:00:00Z",
          "valid_until": null
        }
      ],
      "initiative_refs": [],
      "policy_rule_refs": ["rule-uuid"],
      "decision_snapshot": {"actions": [], "signals": [], "reasons": []},
      "execution": {
        "status": "proposed",
        "failure_reason": null,
        "last_verified_at": null,
        "last_error": null
      },
      "dependencies": []
    }
  ]
}
```

**Item `kind` values**

| Kind | Description |
|---|---|
| `account_create` | Create a new account in the target system |
| `account_invite` | Send an invite (for connectors that use an invite flow) |
| `account_activate` | Re-activate a suspended account |
| `account_suspend` | Suspend an active account |
| `account_disable` | Disable an account (deeper than suspend; may trigger cascades) |
| `grant_role` | Grant a role or permission |
| `revoke_role` | Revoke a role or permission |
| `group_add` | Add the subject to a group |
| `group_remove` | Remove the subject from a group |
| `entitlement_attach` | Attach an entitlement to the subject |
| `entitlement_detach` | Detach an entitlement from the subject |

**Item `execution.status` values**

| Status | Description |
|---|---|
| `proposed` | Not yet started |
| `executing` | Connector call is in progress (or was in progress before a crash) |
| `done` | Successfully applied and verified |
| `failed` | Failed; see `failure_reason` and `last_error` |

**Item `execution.failure_reason` values**

| Value | Meaning |
|---|---|
| `precondition` | A dependency item failed or did not complete |
| `apply_error` | The connector call returned an error |
| `verify_mismatch` | Post-apply verification returned a state different from expected |
| `verify_timeout` | Verification timed out (default 30 s) |

---

## POST /plans/dry-run

Compute a plan without persisting it.

Accepts the same request body as `POST /plans`. Returns the same `AccessPlanRead`
shape but without `id`, `created_at`, or an `execution` block per item (nothing
is stored). `idempotency_key` is accepted but ignored.

The endpoint always returns `200`. It never returns `201`.

Use this for what-if analysis before committing to a change, for admin
debugging, and for UI previews.

---

## GET /plans

List plans. Cursor-paginated.

### Query parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `subject_ref` | UUID | — | Filter by subject |
| `subject_type` | string | — | `employee` or `nhi` |
| `status` | string | — | `active`, `superseded`, `invalid`, `cancelled` |
| `limit` | int | `50` | `1..200` |
| `cursor` | string | — | Opaque cursor from `next_cursor` |

### Response (`200 OK`)

```json
{
  "items": [ { "id": "uuid", "subject_ref": "uuid", "status": "active", "...": "..." } ],
  "next_cursor": "eyJ0cyI6Ii4uLiIsImlkIjoiLi4uIn0"
}
```

`next_cursor` is `null` when the last page has been reached. Cursors are
opaque base64url — see [API Conventions / pagination](../api/overview.md#pagination).

---

## GET /plans/{id}

Fetch a single plan by UUID, including all items and their execution state.

| Code | Condition |
|---|---|
| `200 OK` | Plan found; body is `AccessPlanRead` |
| `404 Not Found` | Plan id unknown |

---

## GET /plans/items

Cross-plan flat list of `PlanItem` rows. Added in Phase 19 H8 so the Studio "Outgoing" tab and the GUI can show pending and executing plan items across the system without iterating per plan. The endpoint JOINs `PlanItemExecution.status` so each item carries its current `execution_status` inline.

### Query parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `status` | string | — | Plan item `execution_status` filter (`proposed`, `executing`, `done`, `failed`) |
| `kind` | string | — | Plan item `kind` filter (see kind table above) |
| `application_id` | UUID | — | Filter to items targeting one application |
| `plan_id` | UUID | — | Filter to a single plan |
| `subject_ref` | UUID | — | Filter to one subject |
| `limit` | int | `100` | `1..1000` |
| `cursor` | string | — | Opaque cursor from `next_cursor` |

### Response (`200 OK`)

```json
{
  "items": [
    {
      "id": "uuid",
      "plan_id": "uuid",
      "kind": "account_create",
      "application": "uuid",
      "application_code": "slack-prod",
      "subject_display": "Иванов Иван",
      "execution_status": "proposed",
      "...": "..."
    }
  ],
  "next_cursor": null
}
```

Items carry the H5 display fields (`subject_display`, `account_display`, `resource_display`, `application_code`, `application_name`, `change_summary`) — same fields the Studio Outgoing tab renders.

### GET /plans/items/count

Same filters as the flat list; returns `{"count": <int>}`. Used by Studio badges.

---

## POST /plans/{id}/apply

Trigger asynchronous execution of an access plan.

### Query parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `confirm_destructive` | bool | `false` | Required when `plan.requires_confirmation = true` |

### Responses

| Code | Condition | Body |
|---|---|---|
| `201 Created` | New pipeline run started | `{"pipeline_run_id": "uuid"}` |
| `200 OK` | Idempotent: a run for this exact plan is already active; same `pipeline_run_id` returned | `{"pipeline_run_id": "uuid"}` |
| `404 Not Found` | Plan id unknown | error |
| `409 Conflict` | Plan is not `active` (`superseded`, `invalid`, or `cancelled`), or another plan for the same subject is currently applying | error with `code` |
| `422 Unprocessable Entity` | `requires_confirmation` is `true` but `confirm_destructive` was not set | error with `code: destructive_threshold_exceeded` |

**409 codes**

| `code` | Meaning |
|---|---|
| `plan_not_active` | Plan status is not `active`. `invalidation_reason` included when available. |
| `apply_in_progress_for_subject` | A different plan for the same subject is currently being applied. `existing_pipeline_run_id` and `existing_plan_id` included. |

---

## Events emitted

The following domain events are published to `aurelion.events` during plan
and apply operations.

| `event_type` | When |
|---|---|
| `access_plan.created` | A new plan is persisted (not emitted for deduplication reuse) |
| `access_plan.superseded` | An existing `active` plan is superseded by a new one |
| `access_plan.invalid` | A plan's status is set to `invalid` (either `structural` or `stale_after_apply`) |
| `plan_item.executed` | A single `PlanItem` transitions to `done` |
| `plan_item.failed` | A single `PlanItem` transitions to `failed` |

All events carry `correlation_id` propagated from the originating HTTP request
header `X-Correlation-ID`. If the header is absent, the kernel generates one.
See [Events and Logs](../concepts/events.md) for envelope shape.

---

## Source of truth

- `aurelion-kernel/src/engines/access_plan/routes.py`
- `aurelion-kernel/src/engines/access_plan/schemas.py`
