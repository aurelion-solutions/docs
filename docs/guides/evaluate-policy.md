# How to evaluate a policy decision

The Policy Decision Point (PDP) answers whether a specific subject is permitted to perform a specific action on a specific resource. This guide shows how to construct a request and interpret the result.

## What the PDP needs

A policy evaluation request is a JSON document called **Facts**, containing three sections:

- `subject` — who is asking (type, status, attributes)
- `target` — what they want to access (application, resource, action)
- `threat` — optional signals about known threats or anomalies

## Step 1: Write a Facts document

Save this as `facts.json`:

```json
{
  "subject": {
    "type": "employee",
    "status": "active",
    "attributes": {
      "department": "engineering",
      "employment_status": "active",
      "mfa_enrolled": "true",
      "risk_score": "12"
    }
  },
  "target": {
    "application": "github",
    "resource_type": "repository",
    "resource_key": "org/backend",
    "action": "write"
  },
  "threat": {}
}
```

`target.application` must match the `code` of a registered application. The PDP uses it to load the right policy rules and action mapping.

## Step 2: Evaluate

Via CLI:
```bash
al policy evaluate --file facts.json
```

Via stdin:
```bash
cat facts.json | al policy evaluate
```

Via API:
```bash
curl -X POST http://localhost:8000/api/v0/policy/evaluate \
  -H "Content-Type: application/json" \
  -d @facts.json
```

## Step 3: Read the decision

```json
{
  "decision": "allow",
  "risk_level": "low",
  "signals": [],
  "reasons": ["subject is active, no threat signals"],
  "actions": []
}
```

| Field | What it means |
|---|---|
| `decision` | The access verdict: `allow`, `deny`, `mfa_required`, `step_up`, etc. |
| `risk_level` | Aggregated risk: `low`, `medium`, `high`, `critical` |
| `signals` | Which risk or threat signals fired (e.g. `lifecycle.terminated`, `credential.exposed`) |
| `reasons` | Human-readable explanation of the decision |
| `actions` | Concrete remediation actions mapped for this application (e.g. `deactivate_account`) |

## Common scenarios

### Terminated employee

```json
{
  "subject": {
    "type": "employee",
    "status": "active",
    "attributes": {
      "employment_status": "terminated"
    }
  },
  "target": {
    "application": "github",
    "resource_type": "repository",
    "resource_key": "org/backend",
    "action": "read"
  },
  "threat": {}
}
```

Expected: `decision: deny`, signal `lifecycle.terminated`.

### NHI with exposed credential

```json
{
  "subject": {
    "type": "nhi",
    "status": "active",
    "attributes": {}
  },
  "target": {
    "application": "aws",
    "resource_type": "iam_role",
    "resource_key": "arn:aws:iam::123456789:role/deploy",
    "action": "use"
  },
  "threat": {
    "credential_exposed": true
  }
}
```

Expected: `decision: deny`, signal `credential.exposed`, `risk_level: critical`.

## Troubleshooting

**Empty `signals` and unexpected decision** — check that your attribute names match what the policy rules reference. Attribute key names are case-sensitive.

**`decision: allow` when you expect deny** — the relevant rule may not exist yet, or `target.application` may not match any rule's `application` filter. Check `resources/policies/` for the application's rule file.

**`422 Validation error`** — the Facts JSON is malformed or missing required fields. The error body will describe which field failed.
