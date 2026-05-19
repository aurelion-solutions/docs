# Account

A normalized remote account in a specific Application — the identity that exists on the other side of the connector (username in AD, login in GitHub, etc.). Accounts are created and updated by reconciliation, not manually.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `application_id` | UUID | FK to Application |
| `username` | string | Account identifier in the remote system |
| `email` | string | Account email |
| `status` | enum | `active`, `suspended`, `disabled`, `deleted`, `unknown` |
| `subject_id` | UUID | FK to Subject — bind to link the account to an identity |
| `is_privileged` | boolean | Privileged account flag |
| `mfa_enabled` | boolean | MFA status on the account |

## List response display fields

`GET /api/v0/accounts` items also carry read-only display fields, letting list UIs render human-readable strings without N+1 lookups:

| Field | Type | Notes |
|---|---|---|
| `subject_display` | string \| null | Display name of the bound subject (employee or NHI); falls back to UUID |
| `application_code` | string \| null | The owning application's `code` |
| `application_name` | string \| null | The owning application's display name |

All display fields are nullable and fall back to UUIDs when the resolver finds no display value. They are populated by `batch_*_display` helpers in `display_lookups.py` — single round trip, no N+1.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/accounts` | List, filter by `application_id`, `status`, `subject_id`. Items carry display fields. |
| `GET` | `/api/v0/accounts/{id}` | Get by ID |
| `PATCH` | `/api/v0/accounts/{id}` | Update `status` and/or `subject_id` |
| `POST` | `/api/v0/accounts/bulk` | Lake-first bulk ingest from a connector |

Create and delete of individual rows are managed by reconciliation and provisioning, not directly. Bulk ingest writes to the lake; the diff against PG happens in a reconciliation run.

### POST /accounts/bulk

Lake-first ingest. The request body is a list of normalized account rows; the kernel writes them into the `raw.accounts` Iceberg table via `AccountLakeService` and returns a small envelope. The PG `accounts` table is **not** touched by this call — a subsequent `POST /inventory-reconciles/runs` with `entity_type=account` reads the snapshot, diffs against PG, and persists delta items. Apply (via `auto_apply` or `manual_apply`) is what mutates PG.

Response (`200`):

```json
{
  "row_count": 1500,
  "snapshot_id": "739281450821"
}
```

| Code | Condition |
|---|---|
| 200 | Rows written to `raw.accounts`. `snapshot_id` is the new Iceberg snapshot. |
| 404 | Application not found |
| 422 | Validation failure |

The diff itself is driven by `run_accounts_reconciliation` in `master_data_pipeline.py`. All five master-data entities — `persons`, `employees`, `org_units`, `access_artifacts`, and `accounts` — follow the same lake-first pattern.

## CLI

| Command | Description |
|---|---|
| `al inventory accounts list` | List all accounts |
| `al inventory accounts list --application <id>` | Filter by application |
| `al inventory accounts list --status <status>` | Filter by status |
| `al inventory accounts list --subject <id>` | Filter by subject |
| `al inventory accounts get <id>` | Get by ID |
| `al inventory accounts update <id> --status <status>` | Update status |
| `al inventory accounts update <id> --subject <id>` | Bind to subject |
