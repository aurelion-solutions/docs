# Policy Catalog

Read-only, product-neutral list of every policy known to the platform. The
endpoint unifies two underlying sources into one shape so that callers do
not have to know whether a policy is stored in Postgres or on disk.

## Conceptual model

A policy is a definition that produces findings. Every policy is positioned
on three axes:

| Axis | Values |
|---|---|
| `policy_type` | `sod`, `access_risk`, `lifecycle`, `nhi`, `privileged_access` |
| `definition_source` | `db`, `file` |
| `assessment_strategy` | `deterministic`, `heuristic`, `semantic_assisted`, `hybrid` |

SoD is **not** a separate category from cartridges. SoD is `policy_type=sod`
with `definition_source=db`. Lens cartridges are policies with
`definition_source=file`.

## `GET /api/v0/policies/catalog`

Returns the unified catalog.

### Query parameters

None.

### Response — `PolicyCatalogResponse`

| Field | Type | Notes |
|---|---|---|
| `items` | `PolicyCatalogItem[]` | All policies, sorted by `policy_type`, then `definition_source`, then `name`, then `id` |

### `PolicyCatalogItem`

| Field | Type | Notes |
|---|---|---|
| `id` | string | Stable identifier. SoD rules use `sod.rule.<code>`. File cartridges use the manifest `id` (e.g. `lens.access_risk.orphaned_access`). |
| `name` | string | Human-readable name |
| `description` | string \| null | Optional |
| `policy_type` | enum | See axes above |
| `definition_source` | enum | `db` or `file` |
| `assessment_strategy` | enum | See axes above |
| `status` | enum | `active`, `inactive`, or `available` (see below) |
| `version` | int \| null | Cartridge manifest version. `null` for DB-backed SoD rules. |

### Sources

| Source | Origin | `policy_type` | `definition_source` | `assessment_strategy` | `status` |
|---|---|---|---|---|---|
| SoD rule | `sod_rules` table | `sod` | `db` | `deterministic` | `active` if `is_enabled=true`, else `inactive` |
| Lens cartridge | `cartridges/lens/**/*.yaml` | from manifest | `file` | from manifest | always `available` |

Templates under `cartridges/templates/**` are intentionally excluded — they
are skeletons, not runnable policies.

### Out of scope

The catalog is a list, not a control plane. It does **not** expose:

- mitigations
- findings
- per-application coverage
- matched scan results
- editing or toggle APIs

Editing SoD rules continues to go through the `POST /api/v0/sod-rules/apply`
endpoint (see [CLI — Access Analysis](../cli/access-analysis.md) for the
config-as-code workflow). File cartridges are not editable via
the API by design.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/policies/catalog` | Unified policy list |

The endpoint is read-only. It emits one INFO log per call under the
`inventory.policy.catalog` component (`computed`) and emits no events.

## CLI

No CLI surface. The endpoint is consumed directly by the kernel client
(Lens, Engineering Studio, GUI).
