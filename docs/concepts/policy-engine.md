# Policy Decision Point

The PDP answers one question: *is this access permitted?*

It is stateless: it receives context as input, applies rules, and returns a decision. No state between requests, no database calls during evaluation.

## What goes in

A request to the PDP contains three parts:

**SubjectFacts** — who is requesting access:
- Principal type (employee, nhi, customer)
- Status (active, suspended, locked, terminated, ...)
- Attributes (department, risk_score, mfa_enrolled, etc.)

**TargetFacts** — what is being accessed:
- Application code
- Resource type and key
- Required Action

**ThreatFacts** — threat context (optional):
- Behavioral anomalies
- Compromised credentials
- Attack indicators

## How the decision is made

**Step 1: Rule selection.** The PDP loads YAML files from `resources/policies/` at startup. Rules are filtered by `subject_type`, `application`, and `resource_type` — only relevant ones are evaluated. (This is the legacy *rule-pack* path. File-based **policy cartridges** under `cartridges/lens/<policy_type>/*.yaml` use a different evaluator — see [Strategies](#strategies) and [Policy Cartridges](policy-cartridges.md).)

**Step 2: Condition evaluation.** Each rule contains conditions over SubjectFacts and ThreatFacts attributes. Supported operators:

| Operator | Example |
|---|---|
| Equality | `subject.status: terminated` |
| Boolean | `subject.mfa_enabled: false` |
| Null check | `subject.owner: null` |
| Temporal comparison | `subject.start_date: "> now"` |
| Temporal range | `subject.expires_at: "now..now+30d"` |
| Numeric comparison | `threat.risk_score: "> 0.9"` |
| Numeric range | `threat.risk_score: "0.7..0.9"` |
| Initiative type | `target.has_initiative: grace` |
| Threat indicator | `threat.has_indicator: credential_compromised` |

Temporal ranges are left-inclusive, right-exclusive.

**Step 3: Precedence resolution.** If multiple rules fired with conflicting signals, priority is determined by `precedence`. At equal precedence, deny always overrides allow.

**Step 4: Mapping.** The abstract decision (allow / deny / mfa_required) is mapped to concrete actions for the specific Application via `mapping.yaml`. One Application might interpret `deny` as account deactivation; another as role removal.

## What comes out

```
decision:    allow | deny | mfa_required | step_up | ...
risk_level:  low | medium | high | critical
signals:     [list of signals that fired]
reasons:     [list of reasons for the decision]
actions:     [concrete actions for this Application]
```

## Rules in YAML

```yaml
- id: block_terminated_employee
  subject_type: employee
  conditions:
    - field: subject.employment_status
      operator: equals
      value: terminated
  signal: lifecycle.terminated
  decision: deny
  precedence: 100
```

Rules are declarative and do not require a service restart when changed — the PDP reads them at startup.

## Generative method

Phase 19 added a second top-level entry point alongside the per-request evaluator: `policy_assessment.generative`. It is stateless and answers a different question — not "is this single access decision allow or deny", but "given this subject's context, what facts should they hold right now?".

```
(subject_ref, subject_type, subject_context,
 current_facts, current_initiatives) -> list[ProjectedFact]
```

Each `ProjectedFact` carries a `Decision` with `actions`, `signals`, and `reasons` — same shape as the per-request evaluator output. This is what the `access_plan` engine consumes to compute desired state. The method is pure: no DB writes, no events, no logging side effects.

See [Declarative Access Planning](access-planning.md) for the end-to-end flow.

## Strategies

The PDP is a dispatcher in front of two assessment strategies, plus a third evaluation path for file-based policy cartridges:

- **`deterministic` (rule-pack)** — YAML rule-pack evaluation under `resources/policies/`, the path described above. The historical default for atomic policy decisions.
- **`deterministic` (file-based policy cartridge)** — same `deterministic` strategy on the dispatcher level, but routed to `evaluate_deterministic_cartridge` when the request's `policy_definition` carries a `condition` block. Inputs are plain context dicts, not the `Facts` schema. Used by all cartridge-backed callers (Access Analysis: orphan / terminated / unused). See [Policy Cartridges](policy-cartridges.md) for the DSL.
- **`semantic_assisted`** — semantic evidence extraction layered on top of the deterministic path. Uses the LLM platform (`platform/llm`) only as inference infrastructure; the engine itself owns *how* the semantic evidence is incorporated into a decision. The engine never speaks of "LLM-assisted" — that wording confuses the boundary.

The dispatcher (`engines/policy_assessment/dispatcher.py`) routes a `PolicyAssessmentRequest` to one of the strategies under `engines/policy_assessment/strategies/`. The output is a `PolicyAssessmentOutput` (carrying a `Decision` and the supporting evidence) defined in `engines/policy_assessment/contracts.py`.

`PolicyType` and `AssessmentStrategy` enums are owned by **`src/inventory/policy/enums.py`** (Layer 1). The legacy `engines/policy_assessment/enums.py` is a re-export shim kept only for old import paths.

Policy types are organized under `engines/policy_assessment/policy_types/`. Each is a domain-family package (`sod/`, `access_risk/`, `lifecycle/`).

## Policy types

A **policy type** is the *evaluation mechanism* — the domain family of checks that share a contract, a shape of input, and a shape of output. It is not a single rule. Inside a policy type live one or more **policy cartridges** — the concrete pure evaluators that answer a yes/no question about a specific access condition.

A policy type owns no orchestration, no batching, no persistence — those concerns belong to whoever calls it (the PDP for on-demand checks, Access Analysis for batch scans).

The catalogue today:

| Policy type | Domain family | Runtime path | Policy cartridges shipped today |
|---|---|---|---|
| `sod` | Segregation of Duties — forbidden capability combinations on a single subject | DB-backed (rules in `SodRule` rows; pure evaluator in `policy_types/sod/`) | the SoD rule evaluator |
| `access_risk` | Risk-shaped findings on existing access | file-based policy cartridges via `PolicyCartridgeAssessmentService` | `orphaned_access.yaml`, `unused_access.yaml` |
| `lifecycle` | Subject-lifecycle violations on existing access | file-based policy cartridges via `PolicyCartridgeAssessmentService` | `terminated_subject_access.yaml` |

Planned policy types — placeholders in the enum, not yet wired:

| Policy type | Will cover |
|---|---|
| `nhi` | Non-human identity hygiene checks |
| `privileged_access` | Privileged-access governance checks |

Each policy type lives in its own subdirectory under `engines/policy_assessment/policy_types/` and exposes a uniform contract. For cartridge-backed types, the *evaluator subdirectory* still exists but the runtime call goes through the cartridge service; the legacy `detect_*` functions remain as library helpers and as fallbacks.

### SoD stays DB-backed

SoD is intentionally **not** expressed as a policy cartridge. The reasons:

- Each `SodRule` carries its own conditions (capability sets), severity, and scope mode (`global` / `per_application` / `by_scope_key`).
- Mitigation resolution (specific-overrides-generic, active-vs-proposed) is a multi-step Python algorithm.
- Evidence-hash computation depends on concrete grant IDs.

A documentation-only template lives at `cartridges/templates/sod/toxic_combination.template.yaml`. It is **never loaded** by `FileCartridgeLoader`. Operators who want to inspect what an SoD evaluation conceptually looks like can read that file; it has no runtime effect.

## Severity for policy-cartridge-backed findings

Findings produced through the policy-cartridge path (orphan, terminated,
unused) take their severity from the cartridge YAML, not from the engine
code. `ScanEngine` resolves severity from `output.decision.risk_level →
SodSeverity`; the per-policy `DEFAULT_*_SEVERITY` Python constants are a
fallback only, used when the cartridge response carries no `Decision`.

A consequence of this design: a YAML edit changes severity for new
findings on the next scan, with no kernel code change involved.

For the procedure, see the [Policy Cartridge Operations](../operations/policy-cartridge-operations.md) runbook.

## Where it lives

`src/engines/policy_assessment/` — the Engines layer (dispatcher, cartridge service, strategy implementations, policy_type evaluators).

`src/inventory/policy/cartridges/` — the Inventory layer (`FileCartridgeLoader`, `CartridgeManifest` schema). No engine import allowed in the other direction.

`cartridges/lens/<policy_type>/*.yaml` — runnable file-based policy cartridges (root of the monorepo).

`cartridges/templates/` — documentation-only YAML; never loaded.

To call: `POST /api/v0/policy/evaluate` or `al policy evaluate` (rule-pack path); policy cartridges are invoked indirectly by Access Analysis on every scan run.
