# Access Fact

The normalized current-state access record: "Subject X has Action Y on Resource Z." This is what downstream engines (PDP, EAS, `access_plan`) consume. Facts are created and revoked by `inventory_sync`; the REST surface is read-only.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `subject_id` | UUID | FK to Subject (XOR with `account_id`) |
| `account_id` | UUID | FK to Account (XOR with `subject_id`) |
| `resource_id` | UUID | FK to Resource |
| `action_slug` | string | One of the seven seeded action slugs |
| `effect` | string | `allow` or `deny` |
| `is_active` | boolean | False when revoked |
| `revoked_at` | datetime \| null | Set when the fact is revoked; nullable for active rows |
| `valid_from` | datetime \| null | Start of validity window; nullable |
| `valid_until` | datetime \| null | End of validity window; nullable |
| `observed_at` | datetime \| null | When the connector last saw this fact; nullable |
| `event_key` | string \| null | Wire-level idempotency key `hash(plan_item_id, op)`. Set when the fact was produced by an `access_plan` apply via `inventory_sync.sync_single_fact`; null for reconciliation-driven writes. |

`valid_from`, `valid_until`, `observed_at`, and `revoked_at` are nullable on `AccessFactView`/`AccessFactRead` to match the lake schema.

## List response display fields

`GET /api/v0/access-facts` items carry read-only display fields populated by `batch_*_display` helpers:

| Field | Type | Notes |
|---|---|---|
| `subject_display` | string \| null | Display name of the bound subject; resolved via `subjects.id → employees | nhis → persons` |
| `account_display` | string \| null | Account's `username` |
| `resource_display` | string \| null | Resource label |
| `application_code` | string \| null | Owning application's `code` |
| `application_name` | string \| null | Owning application's display name |
| `change_summary` | string \| null | Short human-readable summary of the last change (e.g. "granted by birthright") |

All display fields are nullable and fall back to UUIDs when no display value is available.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/access-facts` | List, filter by `subject_id`, `resource_id`, `account_id`, `action_slug`, `effect`, `is_active`, `valid_at`. Items carry display fields. |
| `GET` | `/api/v0/access-facts/{id}` | Get by ID |

Read-only. Facts are managed exclusively by `inventory_sync` (see [Reconciliation reference / Apply runs](reconciliation.md#apply-runs)) and by `access_plan` apply via `inventory_sync.sync_single_fact`. `inventory.access_fact.{created,updated,revoked,reactivated}` events are emitted only from that engine and carry `delta_item_id`, `snapshot_id`, and `reconciliation_run_id` (the latter is null for plan-driven writes).

## CLI

| Command | Description |
|---|---|
| `al inventory access-facts list` | List all facts |
| `al inventory access-facts list --subject <id>` | Filter by subject |
| `al inventory access-facts list --resource <id>` | Filter by resource |
| `al inventory access-facts list --action-slug <slug>` | Filter by action |
| `al inventory access-facts list --effect <effect>` | Filter by effect |
| `al inventory access-facts list --valid-at <iso>` | Filter by validity window |
| `al inventory access-facts get <id>` | Get by ID |
