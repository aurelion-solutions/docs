# Policy Cartridges

A **policy cartridge** is a self-contained YAML file that declares a single
detection rule: what to look at, when it fires, what severity to assign,
and what remediation to suggest. Policy cartridges turn detection rules
into versionable, human-readable artifacts that operators can edit without
touching engine code.

This page explains the conceptual model. For the YAML schema and the DSL
operator reference, see [Policy Cartridges (reference)](../reference/policy-cartridges.md).

## Where policy cartridges live

The monorepo exposes two top-level cartridge directories:

```
cartridges/
  lens/                         # runnable, evaluated at scan time
    access_risk/
      orphaned_access.yaml
      unused_access.yaml
    lifecycle/
      terminated_subject_access.yaml
  templates/                    # documentation-only, never loaded
    sod/
      toxic_combination.template.yaml
```

`cartridges/lens/<policy_type>/*.yaml` is the **only** location the kernel
loads at runtime. Everything under `cartridges/templates/` is documentation
and is intentionally invisible to `FileCartridgeLoader`.

The directory name `lens` here refers to a *security policy lens
namespace* — a way of grouping checks that look at the same governance
question from different angles. It is not a product name.

## Anatomy of a policy cartridge

```yaml
id: lens.access_risk.orphaned_access
version: 1
name: Orphaned Access
description: >
  Detects active accounts where no corresponding active subject exists.
policy_type: access_risk
rule_id: lens.access_risk.orphaned_access
assessment_strategy: deterministic
requires:
  subject.id: string
condition:
  equals:
    fact: subject_not_found
    value: true
decision:
  action: flag_for_review
  risk_level: high
finding:
  title: Orphaned Access Detected
  severity: high
  remediation: >
    Revoke or reassign the access grant.
```

The blocks:

- **`id`** — unique slug, dotted form `lens.<policy_type>.<name>`.
- **`policy_type`** — domain family (one of the [PolicyType](policy-engine.md#policy-types) values). Must match the parent directory name.
- **`assessment_strategy`** — always `deterministic` for runnable cartridges today.
- **`requires`** — declared input shape. Documentation; not currently enforced at runtime.
- **`condition`** — a node in the cartridge DSL. The cartridge fires if the condition is `True` against the engine's context dict.
- **`decision`** — the `Decision` returned to the caller when the cartridge fires. `risk_level` is the source of truth for the resulting finding's severity.
- **`finding`** — display metadata used by UI and remediation guidance.

## The DSL — what `condition` can do

The condition language is intentionally small. It evaluates against a plain
context dict and supports seven operators:

| Operator | Form | Meaning |
|---|---|---|
| `all` | list of nodes | every child must match |
| `any` | list of nodes | at least one child must match |
| `equals` | `{fact, value}` | `context[fact] == value` |
| `not_equals` | `{fact, value}` | `context[fact] != value` |
| `is_null` | `{fact}` or `"path"` | `context[fact] is None` |
| `is_not_null` | `{fact}` or `"path"` | `context[fact] is not None` |
| `greater_than` | `{fact, value}` | `float(context[fact]) > float(value)` |

Fact paths are dot-separated and resolved against nested dicts:
`subject.status` looks up `context["subject"]["status"]`.

There is no `less_than`, no string matching, no arithmetic, no
context-variable thresholds. Severity comes from the `decision` block, not
from the DSL. If a check needs more expressive power than the DSL provides,
it does not belong in a cartridge — keep it in Python.

## Severity is owned by the cartridge

For findings produced through the policy-cartridge path, the cartridge YAML
is the **source of truth** for severity. `ScanEngine` resolves severity
like this:

1. If `output.decision.risk_level` is set → convert to `SodSeverity` and use that.
2. Otherwise → fall back to the per-policy `DEFAULT_*_SEVERITY` constant.

The fallback exists for tests that mock `PolicyAssessmentOutput(matched=True)`
without a `Decision`; in production the cartridge always returns a
`Decision`, so the YAML always wins.

This means:

- A YAML edit to `cartridges/lens/lifecycle/terminated_subject_access.yaml`
  changes the severity of new `terminated_subject_access` findings on the
  next scan. No kernel code change is required.
- The Python `DEFAULT_*_SEVERITY` constants in
  `engines/policy_assessment/policy_types/.../evaluator.py` are *not* the
  authoritative number for cartridge-backed paths. They are defaults of
  last resort.

## How a policy cartridge gets evaluated

```
ScanEngine.run()
    │
    ▼
PolicyCartridgeAssessmentService.evaluate_file(path, context)
    │
    ├─ FileCartridgeLoader.load_file(path)         # inventory layer
    │     → CartridgeManifest (Pydantic v2)
    │
    ├─ cartridge_manifest_to_request(manifest, context)
    │     → PolicyAssessmentRequest
    │
    └─ PolicyAssessmentDispatcher.evaluate(request)
          → routes to evaluate_deterministic_cartridge
          → returns PolicyAssessmentOutput(matched, decision, payload)
```

Three layers, three responsibilities:

- **Inventory** (`src/inventory/policy/cartridges/`) parses YAML and
  validates the manifest. It does not know what an engine is.
- **Adapter** (`src/engines/policy_assessment/cartridge_adapter.py`) turns
  the manifest into an engine request. This is the only direction the
  layering allows: engine reads from inventory, never the reverse.
- **Engine** (`src/engines/policy_assessment/strategies/deterministic/cartridge_evaluator.py`)
  walks the DSL condition against the context and builds the output.

`ScanEngine` itself never opens a YAML file or instantiates a manifest. It
only knows the path to the cartridge and the context dict it built from
loaded scan data.

## What policy cartridges are not for

- **Stateful logic.** Mitigation resolution, evidence-hash computation,
  cross-grant intersection — none of this is expressible in seven
  operators against a flat dict, and shouldn't be forced.
- **SoD evaluation.** SoD requires per-rule capability sets, scope buckets,
  and mitigation precedence. It stays DB-backed; see
  [Policy Decision Point — SoD stays DB-backed](policy-engine.md#sod-stays-db-backed).
- **Persistence.** A policy cartridge returns a decision; it does not write
  findings, emit events, or commit transactions.
- **Configuration.** A policy cartridge is a *rule*, not a feature flag.
  Feature flags live in the product layer.

## Where to go next

- [Policy Cartridges (reference)](../reference/policy-cartridges.md) — YAML schema, DSL operators, manifest validation rules.
- [Add a policy cartridge](../guides/add-policy-cartridge.md) — step-by-step guide for adding a new policy cartridge to a kernel checkout.
- [Policy Cartridge Operations](../operations/policy-cartridge-operations.md) — pre-flight, deploy, verify, and rollback procedure for a running deployment.
