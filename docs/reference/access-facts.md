# Access Fact

The normalized current-state access record: "Subject X has Action Y on Resource Z." This is what downstream engines (PDP, SoD, EAS) consume. Facts are created and revoked by `SyncApplyService` from approved reconciliation delta items; the REST surface is read-only.

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
| `revoked_at` | datetime | Set when the fact is revoked |
| `valid_from` | datetime | Start of validity window (nullable) |
| `valid_until` | datetime | End of validity window (nullable) |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/access-facts` | List, filter by `subject_id`, `resource_id`, `account_id`, `action_slug`, `effect`, `is_active`, `valid_at` |
| `GET` | `/api/v0/access-facts/{id}` | Get by ID |

Read-only. Facts are managed exclusively by `SyncApplyService` (see [Reconciliation reference / Apply runs](reconciliation.md#apply-runs)). `inventory.access_fact.{created,updated,revoked,reactivated}` events are emitted only from that service and carry `delta_item_id`, `snapshot_id`, and `reconciliation_run_id`.

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
