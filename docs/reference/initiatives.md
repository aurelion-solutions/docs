# Initiative

Records *why* an AccessFact exists — the business justification behind a grant. An initiative is always linked to an AccessFact, carries a typed origin, and an optional validity window.

Initiatives are immutable for audit purposes. To remove access, revoke the AccessFact; the linked initiative is **not deleted**, its `valid_until` is set to `now()` so the audit trail survives the revoke. Phase 19 codified this — there is no delete endpoint by design.

## Typed origin

Phase 19 made initiatives the canonical metadata-on-access-fact carrier with a structured `origin` string. The format is `<type>:<id>` and is consumed by `policy_assessment.generative` to decide whether a fact survives the next replan.

| `type` | `origin` format | Meaning |
|---|---|---|
| `birthright` | `policy_rule:<rule_id>` | Granted by a policy rule (e.g. department membership) |
| `requested` | `request:<request_id>` | Granted via an access request |
| `delegated` | `delegation:<delegator_subject_ref>` | Delegated by another subject |
| `grace` | `grace:<source_initiative_id>` | Grace period following revocation of the source initiative |
| `inherited` | implementation-specific | Inherited from a group or org-unit ancestor |
| `self_registered` | implementation-specific | Subject registered themselves |
| `invited` | implementation-specific | Granted via invite flow |
| `trial` | implementation-specific | Time-bounded trial access |
| `subscription` | implementation-specific | Subscription-driven access |

`policy_rule:<rule_id>` and `grace:<source_initiative_id>` are load-bearing for the declarative-planning flow — they let `policy_assessment.generative` distinguish "this should be re-emitted from the same rule" from "this came from elsewhere and stays put".

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `access_fact_id` | UUID | FK to AccessFact |
| `type` | enum | See typed-origin table above |
| `origin` | string | `<type>:<id>` (see typed-origin table) |
| `valid_from` | datetime | Start of validity window |
| `valid_until` | datetime \| null | End of validity window (null = open-ended; set to `now()` on revoke) |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/initiatives` | List, filter by `access_fact_id`, `type` |
| `GET` | `/api/v0/initiatives/{id}` | Get by ID |
| `POST` | `/api/v0/initiatives` | Create |
| `PATCH` | `/api/v0/initiatives/{id}` | Update `origin`, `valid_from`, `valid_until` |

No `DELETE` — revoking an access fact sets the initiative's `valid_until` to `now()` rather than removing the row.

## CLI

| Command | Description |
|---|---|
| `al inventory initiatives list` | List all initiatives |
| `al inventory initiatives list --access-fact <id>` | Filter by access fact |
| `al inventory initiatives list --type <type>` | Filter by type |
| `al inventory initiatives get <id>` | Get by ID |
| `al inventory initiatives create --access-fact <id> --type <type> --origin <text>` | Create |
| `al inventory initiatives update <id> --origin <text>` | Update origin |
| `al inventory initiatives update <id> --valid-until <iso>` | Set expiry |
