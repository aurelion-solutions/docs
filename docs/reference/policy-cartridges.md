# Policy Cartridges (reference)

This page is the schema reference for file-based policy cartridges. For
the conceptual model — what policy cartridges are, why they exist, how
they fit into scan orchestration — see
[Policy Cartridges (concepts)](../concepts/policy-cartridges.md).

## File layout

Runnable policy cartridges:

```
cartridges/lens/<policy_type>/<name>.yaml
```

The directory immediately under `lens/` MUST equal the cartridge's
`policy_type` field. The structural test
`test_cartridges_grouped_by_policy_type` enforces this.

Documentation-only templates:

```
cartridges/templates/<policy_type>/<name>.template.yaml
```

`FileCartridgeLoader` MUST NOT be pointed at `cartridges/templates/`. The
`.template.yaml` extension is also a soft guard — keep it for clarity, but
the load-path discipline is the load-bearing rule.

## YAML schema

A policy cartridge is a YAML mapping with the following top-level keys.
All keys are required unless marked optional.

| Key | Type | Notes |
|---|---|---|
| `id` | string | Globally unique slug. Convention: `lens.<policy_type>.<name>`. |
| `version` | int | Schema version of this cartridge. Currently `1`. Must be an integer, not a string. |
| `name` | string | Human-readable display name. |
| `description` | string | Optional. Multi-line YAML strings are fine. |
| `policy_type` | string | One of the `PolicyType` values: `sod`, `access_risk`, `lifecycle`, `nhi`, `privileged_access`. Must equal the parent directory name. |
| `rule_id` | string | Stable identifier carried into the `Decision`. Convention: same as `id`. Must NOT equal `policy_type`. |
| `assessment_strategy` | string | One of the `AssessmentStrategy` values. For runnable cartridges today, always `deterministic`. |
| `requires` | mapping | Declared input shape. Documentation-only at runtime. |
| `condition` | mapping | A node in the DSL — see below. |
| `decision` | mapping | What to return when the condition matches. See below. |
| `finding` | mapping | Display metadata for the produced finding. See below. |
| `payload` | mapping | Optional. Free-form key/value passed through into `PolicyAssessmentOutput.payload`. |

### `requires` block

A flat mapping declaring the dot-paths the cartridge expects to find in the
context. Values describe the type informally:

```yaml
requires:
  subject.id: string
  subject.status: string
```

Not enforced by the loader at runtime; useful for human review of what
context fields a cartridge depends on.

### `condition` block

A single DSL node. See [DSL operators](#dsl-operators) below.

### `decision` block

```yaml
decision:
  action: flag_for_review        # or list under `actions`
  abstract_state: suspended      # optional, defaults to "suspended"
  risk_level: high               # one of: critical | high | medium | low
```

Field rules:

- `risk_level`: one of `critical`, `high`, `medium`, `low`. Used by ScanEngine to set the persisted finding's severity.
- `actions` (list) is preferred when there are multiple. `action` (singular) is sugar — the evaluator wraps it into a single-item list.
- `abstract_state` defaults to `suspended` when absent.

### `finding` block

```yaml
finding:
  title: Orphaned Access Detected
  severity: high
  remediation: >
    Revoke or reassign the access grant.
```

Display metadata. `severity` here is informational; the *persisted*
finding's severity is taken from `decision.risk_level`. Keep the two
aligned by convention; the engine does not cross-check them.

## DSL operators

The `condition` block is a single node. Each operator is a key on the node
mapping. Unrecognized keys raise `ValueError` at evaluation time.

### `all`

```yaml
condition:
  all:
    - equals: { fact: capabilities_intersect, value: true }
    - greater_than: { fact: conflicting_pair_count, value: 0 }
```

Every child must match. Empty list trivially matches.

### `any`

```yaml
condition:
  any:
    - equals: { fact: subject.status, value: terminated }
    - equals: { fact: subject.status, value: expired }
```

At least one child must match. Empty list trivially does not match.

### `equals`

```yaml
condition:
  equals:
    fact: subject_not_found
    value: true
```

`context[fact] == value`. Standard Python `==`; YAML booleans become
Python booleans.

### `not_equals`

```yaml
condition:
  not_equals:
    fact: subject.status
    value: active
```

`context[fact] != value`. Missing fact is `None` and compares accordingly.

### `is_null`

```yaml
condition:
  is_null:
    fact: account.subject_id
```

Or string sugar:

```yaml
condition:
  is_null: account.subject_id
```

Returns `True` if the dot-path resolves to `None` (including: missing
key, intermediate `None`, intermediate non-dict).

### `is_not_null`

Same as `is_null`, inverted.

### `greater_than`

```yaml
condition:
  greater_than:
    fact: days_since_last_use
    value: 90
```

`float(context[fact]) > float(value)`. Missing or non-numeric fact returns
`False` (does not raise). `None` short-circuits to `False` before the cast.
Numeric strings such as `"123"` are coerced via `float()` and compare numerically
(`"123"` > `100` → `True`). Non-numeric strings (e.g. `"abc"`) return `False`.
This behaviour is covered by the test `test_greater_than_string_ish_numbers_and_none` (Phase 17 Step 15).

## Fact-path resolution

Dot-paths are resolved against nested dicts. Given:

```python
context = {"subject": {"id": "u-1", "status": "expired"}}
```

- `subject.status` → `"expired"`
- `subject.unknown` → `None`
- `unknown.path` → `None` (does not raise)

Lookups never raise; missing intermediate keys silently produce `None`.

## Manifest validation

`FileCartridgeLoader.load_file(path)` performs:

1. YAML parse — raises `CartridgeLoadError` with the underlying YAML error
   on malformed input.
2. Top-level type check — must be a mapping, not a list or scalar.
3. Pydantic v2 validation against `CartridgeManifest`.

`load_dir(path)` recursively globs `*.yaml` under the directory and
validates each. It does not filter `*.template.yaml` — keep templates
out of `cartridges/lens/`.

## Programmatic evaluation

`PolicyCartridgeAssessmentService.evaluate_file(path, context)` is the
public entry point. It returns a `PolicyAssessmentOutput`.

```python
from pathlib import Path
from src.engines.policy_assessment.cartridge_service import (
    PolicyCartridgeAssessmentService,
)

svc = PolicyCartridgeAssessmentService()
result = svc.evaluate_file(
    Path("cartridges/lens/access_risk/unused_access.yaml"),
    {"days_since_last_use": 120},
)
```

The dispatcher branch is selected by the presence of `condition` in
`request.policy_definition`. Cartridges always carry a `condition`; the
legacy `resources/policies/*.yaml` rule-pack path does not.

## Shipped policy cartridges today

| Path | Policy type | Fires when | `risk_level` |
|---|---|---|---|
| `cartridges/lens/access_risk/orphaned_access.yaml` | `access_risk` | `subject_not_found == true` | `high` |
| `cartridges/lens/access_risk/unused_access.yaml` | `access_risk` | `days_since_last_use > 90` | `medium` |
| `cartridges/lens/lifecycle/terminated_subject_access.yaml` | `lifecycle` | `subject.status` ∈ {`terminated`, `expired`, `locked`, `banned`, `deletion_requested`} | `critical` |

Documentation-only:

| Path | Why | Status |
|---|---|---|
| `cartridges/templates/sod/toxic_combination.template.yaml` | Conceptual SoD example | NEVER LOADED. SoD is DB-backed (rules in `SodRule` rows). |
