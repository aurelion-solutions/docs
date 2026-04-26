# Capability Grant

Persisted projection rows produced by the CapabilityProjector: "subject S holds capability C, derived from effective grant E via mapping M, optionally narrowed by a scope key/value pair." Capability grants are the queryable form of the capability projection that powers reports, dashboards, and the SoD evaluator.

Read-only. The projector is the only writer; there is no public write surface.

See [Access Analysis](../concepts/access-analysis.md) for how mappings produce these rows.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | int | Primary key |
| `subject_id` | UUID | The subject that holds the capability |
| `capability_id` | int | FK to `Capability` |
| `application_id` | UUID | Application the underlying grant lives in |
| `scope_key_id` | int \| null | FK to the capability's `CapabilityScopeKey`, when scoped |
| `scope_value` | string \| null | Resolved scope value (e.g. cost centre, amount limit) |
| `source_effective_grant_id` | UUID | The EAS row this projection derives from |
| `source_capability_mapping_id` | int | The mapping rule that fired |
| `is_active` | boolean | False once the source grant is tombstoned or the mapping deactivates |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/capability-grants` | List with filters; **400** if no narrowing filter is supplied |
| `GET` | `/api/v0/capability-grants/{id}` | Get by ID |

`GET /capability-grants` accepts `subject_id`, `capability_id`, `scope_key_id`, `scope_value`, `application_id`, `source_effective_grant_id`, `source_capability_mapping_id`, `active_only` (default `true`), `limit` (1–500, default 100), and `offset`.

At least one of `subject_id`, `capability_id`, `application_id`, `source_effective_grant_id`, or `source_capability_mapping_id` is required. Calls with no narrowing filter return **400 Bad Request** to prevent unbounded full-table scans against a projection that grows with EAS size. `scope_key_id` and `scope_value` alone do not narrow enough — combine them with one of the required filters.
