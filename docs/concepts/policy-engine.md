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

**Step 1: Rule selection.** The PDP loads YAML files from `resources/policies/` at startup. Rules are filtered by `subject_type`, `application`, and `resource_type` — only relevant ones are evaluated.

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

## Where it lives

`src/capabilities/engines/policy_decision_point/` — the Capabilities layer.

To call: `POST /api/v0/policy/evaluate` or `al policy evaluate`.
