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

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/accounts` | List, filter by `application_id`, `status`, `subject_id` |
| `GET` | `/api/v0/accounts/{id}` | Get by ID |
| `PATCH` | `/api/v0/accounts/{id}` | Update `status` and/or `subject_id` |

Create and delete are managed by reconciliation and provisioning, not directly.

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
