# CLI — Access Analysis

Reference for `al` commands that drive the access-analysis surface:
SoD policy management, evaluation, capability resolution, scan runs, findings, and feedback.

All commands accept a global `--base-url` option (defaults to the configured
platform URL) and emit JSON to stdout on success. Errors go to stderr with
exit code `1` for API errors and `2` for client-side validation errors.

See also: [Access Analysis concepts](../concepts/access-analysis.md).

---

## SoD

### `al sod apply` — config-as-code

Apply SoD rules from a YAML or JSON file. **Idempotent** — safe to run on every
deploy. Rules are keyed by `code`; conditions by `name` within a rule.
Capabilities are referenced by slug, not by ID.

| Option | Description |
|---|---|
| `FILE` (positional) | Path to `.yaml`, `.yml`, or `.json` file |
| `--created-by` | Actor identifier recorded on newly created rules |
| `--dry-run` | Print the resolved payload without sending it |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/sod-rules/apply`. Returns 422 if any capability slug is unknown.

**File format** (`sod-rules.yaml`):

```yaml
rules:
  - code: SOD_AP_001
    name: Vendor Creation + Payment Approval
    description: >
      No individual may both create vendor master records and approve
      payment runs. Classic AP four-eyes principle (IFRS / SOX).
    severity: critical        # critical | high | medium | low | informational
    scope_mode: global        # global (default)
    mitigation_allowed: true
    conditions:
      - name: Creates vendors
        min_count: 1          # subject must hold ≥ min_count caps from this set
        capabilities:
          - create_vendor
      - name: Approves payments
        min_count: 1
        capabilities:
          - approve_payment

  - code: SOD_AP_002
    name: Payment Approval + Payment Release
    severity: high
    scope_mode: global
    conditions:
      - name: Approves payments
        min_count: 1
        capabilities: [approve_payment]
      - name: Releases payments
        min_count: 1
        capabilities: [release_payment]
```

```bash
# Apply and record who ran it
al sod apply sod-rules.yaml --created-by ci-pipeline

# Preview what would be sent (no writes)
al sod apply sod-rules.yaml --dry-run
```

Output on success:

```
rules: +2 updated=0 unchanged=0
conditions: +4 -0
```

**What gets updated:** if a rule with the same `code` already exists, its name,
description, severity, and `is_enabled` flag are updated to match the file.
Conditions not present in the file are deleted; new conditions are created;
changed conditions (different `min_count` or capabilities) are replaced.

---

### `al sod evaluate`

Evaluate SoD violations for a subject at a given point in time.

| Option | Description |
|---|---|
| `SUBJECT_ID` (positional) | Subject UUID |
| `--at` | ISO 8601 timestamp; omit for current server time |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/sod/evaluate`.

```bash
al sod evaluate 6f1c0b6a-9b7a-4e0d-a1d5-2b8a4f3c1f10 \
  --at 2026-04-24T09:00:00Z
```

---

### `al sod what-if`

Evaluate SoD violations for a subject with synthetic capability overrides.
An empty override list degenerates to `al sod evaluate`.

| Option | Description |
|---|---|
| `SUBJECT_ID` (positional) | Subject UUID |
| `--override` | Repeatable. Format: `CAP_ID:SCOPE_KEY_ID:SCOPE_VALUE_OR_NULL:APP_UUID`. Use literal `null` for no scope value. |
| `--at` | ISO 8601 timestamp; omit for current server time |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/sod/what-if`.

```bash
al sod what-if 6f1c0b6a-9b7a-4e0d-a1d5-2b8a4f3c1f10 \
  --override 42:7:finance:8d3a1c70-22a9-4e6f-8c4f-9b1f2e3d4a5b \
  --override 43:7:null:8d3a1c70-22a9-4e6f-8c4f-9b1f2e3d4a5b
```

---

### `al sod resolve-capabilities`

Resolve EffectiveGrant sources back to capability slugs.
Input JSON must be either an object with a `sources` key or a top-level list
(automatically wrapped). Reads from `--file` if provided, otherwise from stdin.

| Option | Description |
|---|---|
| `--file` | Path to JSON file. If omitted, reads from stdin. |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/sod/resolve-capabilities`.

```bash
echo '[{"artifact_id": 12, "binding_id": 34}]' \
  | al sod resolve-capabilities
```

---

## Scan Runs

### `al scan run`

Create a scan run and execute it synchronously. Prints the final
`ScanRunRead` JSON after completion.

| Option | Description |
|---|---|
| `--triggered-by` | `manual` (default) \| `api` \| `schedule` |
| `--scope-subject` | Restrict scan to this subject UUID |
| `--scope-application` | Restrict scan to this application UUID |
| `--created-by` | Actor identifier recorded on the run |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/scan-runs` then `POST /api/v0/scan-runs/{id}/run`.

```bash
al scan run \
  --triggered-by manual \
  --scope-application 8d3a1c70-22a9-4e6f-8c4f-9b1f2e3d4a5b \
  --created-by abramovich.michael@gmail.com
```

---

### `al scan list`

List scan runs with optional filters.

| Option | Description |
|---|---|
| `--status` | `pending` \| `running` \| `completed` \| `failed` |
| `--triggered-by` | `manual` \| `api` \| `schedule` |
| `--scope-subject` | Filter by scoped subject UUID |
| `--scope-application` | Filter by scoped application UUID |
| `--limit` | Max results (default `50`) |
| `--offset` | Pagination offset (default `0`) |
| `--base-url` | Platform API base URL |

Calls `GET /api/v0/scan-runs`.

```bash
al scan list --status completed --triggered-by manual --limit 20
```

---

## Findings

### `al findings list`

List findings with audit-style filters.

| Option | Description |
|---|---|
| `--scan-run` | Scan run ID |
| `--rule` | SoD rule ID |
| `--severity` | `critical` \| `high` \| `medium` \| `low` \| `informational` |
| `--status` | `open` \| `acknowledged` \| `resolved` \| `mitigated` |
| `--kind` | `sod` \| `orphan_access` \| `terminated_access` \| `unused_access` |
| `--subject` | Subject UUID |
| `--limit` | Max results (default `50`) |
| `--offset` | Pagination offset (default `0`) |
| `--base-url` | Platform API base URL |

Calls `GET /api/v0/findings`.

```bash
al findings list --severity high --status open --limit 25
```

---

## Feedback

### `al feedback post`

Post structured feedback against a finding, rule, or capability mapping.
At least one of `--rule`, `--mapping`, or `--finding` is required.

| Option | Description |
|---|---|
| `--kind` | `accepted_risk` \| `false_positive` \| `needs_mapping_fix` \| `needs_rule_fix` \| `needs_mitigation` |
| `--message` | Feedback message (required, min length 1) |
| `--rule` | SoD rule ID |
| `--mapping` | Capability mapping ID |
| `--finding` | Finding ID |
| `--subject` | Subject UUID (optional context) |
| `--payload-file` | Path to JSON file included as structured payload |
| `--created-by` | Actor identifier recorded on the feedback |
| `--base-url` | Platform API base URL |

Calls `POST /api/v0/feedbacks`.

```bash
al feedback post \
  --kind false_positive \
  --finding 1287 \
  --message "Compensating control in place — see ticket SEC-4421." \
  --created-by abramovich.michael@gmail.com
```
