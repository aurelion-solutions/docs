# Effective Grants

The read-only HTTP surface over the Effective Access Store (EAS) — the
normalized projection of "who has what access right now". Three
endpoints under `/api/v0/effective-grants`.

The store itself is populated incrementally by `mq_eas_projection_consumer`
from `aurelion.events`. For the projection model see
[Access Analysis](../concepts/access-analysis.md) and
[Events and Logs](../concepts/events.md#effective-access-store-eas).

## Key fields (response shape)

`EffectiveGrantRead` (returned by the list and by-id endpoints):

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Row primary key. Note: the actual storage PK is the three-column `(id, subject_kind, application_id)`; a lookup by `id` alone scans all 12 partitions and must be used for admin / debug only. |
| `subject_id` | UUID | The subject the grant is anchored on. |
| `subject_kind` | enum | `employee`, `nhi`, or `customer`. |
| `application_id` | UUID | Resolved at projection time from the access fact. |
| `account_id` | UUID \| null | Resolved when the underlying fact is account-scoped. |
| `resource_id` | UUID | The resource the grant targets. |
| `action` | enum | The action verb (e.g. `read`, `write`). |
| `effect` | enum | `allow` or `deny`. |
| `initiative_type` | enum | Type of the initiative that produced the grant. |
| `initiative_origin` | string | Initiative origin slug. |
| `valid_from` | datetime | Lower bound of the projection window. |
| `valid_until` | datetime \| null | Upper bound, `null` for open-ended grants. |
| `source_access_fact_id` | UUID | The `access_facts` row this grant projects from. |
| `source_initiative_id` | UUID | The `initiatives` row driving the projection. |
| `observed_at` | datetime | Projection timestamp. |
| `tombstoned_at` | datetime \| null | Set when the grant has been invalidated; rows with this set are excluded by `active_only=true`. |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/effective-grants` | List grants under filters. |
| `GET` | `/api/v0/effective-grants/explain` | Deny-wins aggregation for a `(subject, resource, action)` triple. |
| `GET` | `/api/v0/effective-grants/{grant_id}` | Single grant by id (admin / debug — partition scan). |

### `GET /api/v0/effective-grants`

**Mandatory-filter rule.** At least one of `subject_id`,
`resource_id`, `application_id`, or `source_initiative_id` must be
present; otherwise the endpoint returns `400` `"at least one of
subject_id, resource_id, application_id, source_initiative_id is
required"`. This prevents unbounded full-table scans across the
partitioned store.

Query parameters:

| Name | Type | Default | Notes |
|---|---|---|---|
| `subject_id` | UUID | — | One of the four mandatory filters. |
| `subject_kind` | enum | — | `employee`, `nhi`, `customer`. |
| `application_id` | UUID | — | Mandatory-filter candidate. |
| `account_id` | UUID | — | |
| `resource_id` | UUID | — | Mandatory-filter candidate. |
| `action` | enum | — | |
| `effect` | enum | — | `allow` or `deny`. |
| `initiative_type` | enum | — | |
| `initiative_origin` | string | — | Max length 1024. |
| `source_initiative_id` | UUID | — | Mandatory-filter candidate. |
| `active_only` | bool | `true` | When `true`, restricts to rows with `tombstoned_at IS NULL AND (valid_until IS NULL OR valid_until > now)`. |
| `limit` | int | `100` | `1..1000`. |
| `offset` | int | `0` | `>= 0`. |

Ordering: `observed_at DESC, id DESC`.

### `GET /api/v0/effective-grants/explain`

Returns the deny-wins aggregation of current projection state for a
single `(subject, resource, action)` triple.

> This is a **read-layer aggregation**, not a policy decision. The
> PDP is authoritative for allow/deny verdicts; `/explain` reports raw
> projection rows only.

Query parameters:

| Name | Type | Default | Required |
|---|---|---|---|
| `subject_id` | UUID | — | yes |
| `resource_id` | UUID | — | yes |
| `action` | enum | — | yes |
| `active_only` | bool | `true` | no |

Response — `EffectiveGrantExplainResponse`:

| Field | Type | Notes |
|---|---|---|
| `effect` | enum | `none`, `allow`, or `deny`. |
| `grants` | `EffectiveGrantRead[]` | The matching rows the aggregation was computed over. |

Aggregation rules:

- `none` — no active matching rows exist.
- `allow` — every active match carries `effect=allow`.
- `deny` — at least one active match carries `effect=deny`.

### `GET /api/v0/effective-grants/{grant_id}`

Single grant by `id`. Because the partitioning key is three-column,
a single-id lookup scans every partition. Use for admin / debug
traffic only — do not call from a hot path.

| Status | Meaning |
|---|---|
| 200 | Found |
| 404 | No grant with this `id` |

## Engine actions

The same service surface is reachable as pipeline-callable actions
under the `effective_access` engine. These are the projection write
surface, not the HTTP read surface above.

| Action | Args | Notes |
|---|---|---|
| `effective_access.project_access_fact` | `access_fact_id`, `now`, `correlation_id?` | Re-project one access fact. |
| `effective_access.project_application` | `application_id`, `now`, `correlation_id?` | Re-project every fact for an application. |
| `effective_access.apply_incremental_change` | `change_kind`, `observed_at`, `access_fact_id?` / `initiative_id?`, `correlation_id?`, `causation_event_id?` | Branches: `upsert` and `invalidate_fact` require `access_fact_id`; `invalidate_initiative` requires `initiative_id`. |

Each action emits `eas.projection.completed` post-flush, pre-commit.
A `ValueError` from the projector emits `eas.projection.failed`
instead. See [Pipeline action registry](engine-action-registry.md).

## CLI

No CLI surface. The endpoints are consumed by REST clients directly.

## See also

- [Access Analysis](../concepts/access-analysis.md) — capability
  projection sits on top of EAS.
- [MQ EAS Projection Consumer](../operations/mq-eas-projection-consumer.md)
  — runtime that keeps the store fresh.
