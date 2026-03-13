# Customer

An external human principal — a person using your product as a client, not an employee of the organization. Has tenancy, plan tier, and MFA/lock flags. Status lives on the associated Subject.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `external_id` | string | Identifier in the source system |
| `tenant_id` | string | Tenant scope |
| `tenant_role` | string | Role within the tenant |
| `plan_tier` | string | `free`, `basic`, `pro`, `enterprise` |
| `mfa_enabled` | boolean | Whether MFA is active |
| `is_locked` | boolean | Locks the account |
| `email_verified` | boolean | Email verification status |

Extensible via key-value attributes.

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v0/customers` | Create a customer |
| `GET` | `/api/v0/customers` | List all customers |
| `GET` | `/api/v0/customers/{id}` | Get by ID |
| `PATCH` | `/api/v0/customers/{id}` | Update mutable fields |
| `GET` | `/api/v0/customers/{id}/attributes` | List attributes |
| `POST` | `/api/v0/customers/{id}/attributes` | Add attribute |
| `DELETE` | `/api/v0/customers/{id}/attributes/{key}` | Remove attribute |

## CLI

| Command | Description |
|---|---|
| `al inventory customers list` | List all customers |
| `al inventory customers list --plan <tier>` | Filter by plan tier |
| `al inventory customers list --locked` | Show only locked customers |

Create, update, and attribute management are API-only.
