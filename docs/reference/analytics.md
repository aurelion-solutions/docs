# Analytics

Read-only aggregations over the access-analysis surface. The endpoints
do not mutate state, do not emit events, and do not run an LLM. Each
call returns a freshly-computed snapshot stamped with `generated_at` in
UTC.

Three endpoints share this page because they answer variants of the
same question — "what does the current open-finding population look
like?" — and consumers typically use them together.

For the conceptual role of these surfaces inside the access-analysis
engine, see
[Access Analysis — Analytics surface](../concepts/access-analysis.md#analytics-surface).

## Risk score (MVP)

Two of the three endpoints — `top-risks` and `risk-by-application` —
return a `risk_score`. The score is computed in DuckDB over the Iceberg
`normalized.access_facts` table joined with the Postgres `findings`
table:

```
risk_score = Σ ( severity_weight × open_findings_count_per_severity )
```

Severity weights are named constants in
`src/engines/access_analysis/analytics/schemas.py`:

| Severity | Weight |
|---|---|
| `critical` | 100 |
| `high` | 50 |
| `medium` | 20 |
| `low` | 5 |
| `informational` | 0 (counted in `severity_breakdown` but contributes nothing to `risk_score`) |

Only findings with `status = 'open'` and `subject_id IS NOT NULL`
contribute to the score.

> **MVP, non-canonical.** This is an aggregation score, not the
> Aurelion canonical risk model. It has a known mathematical
> limitation: 100 open `low` findings (5 × 100 = 500) outweigh a single
> `critical` (100). Treat the score as a relative ranking signal, not
> as an absolute risk number, and do not surface it as "the" risk score
> in customer-facing reports. The canonical model is a future-phase
> concern.

## `GET /api/v0/analytics/top-risks`

Top-N `(subject, application)` pairs by `risk_score`.

### Query parameters

| Name | Type | Default | Bounds | Effect |
|---|---|---|---|---|
| `limit` | int | `10` | `1..100` | Caps the number of returned items. Out-of-bounds → 422. |

### Response — `TopRisksResponse`

| Field | Type | Notes |
|---|---|---|
| `items` | `TopRiskItem[]` | Sorted, capped at `limit` |
| `generated_at` | datetime | UTC, stamped after the DuckDB query returns |

### `TopRiskItem`

| Field | Type | Notes |
|---|---|---|
| `subject_id` | UUID | The subject the score is anchored on |
| `application_id` | UUID | Resolved from `access_facts.application_id_denorm` |
| `risk_score` | int | See formula above |
| `open_findings_count` | int | Total open findings for this subject across all severities (equals `sum(severity_breakdown.values())`) |
| `severity_breakdown` | `dict[str, int]` | All five `SodSeverity` keys (`critical`, `high`, `medium`, `low`, `informational`); zero-filled for absent severities. `informational` is counted but contributes 0 to `risk_score`. |

### Sort order

`risk_score DESC`, then `subject_id ASC`, then `application_id ASC`.
The two ascending tie-breakers make the output stable for clients that
diff successive calls.

## `GET /api/v0/analytics/risk-by-application`

Risk aggregated per `application_id`. Returns every application that
has at least one open finding contributing to a non-zero score; not
capped.

### Query parameters

None.

### Response — `RiskByApplicationResponse`

| Field | Type | Notes |
|---|---|---|
| `items` | `RiskByApplicationItem[]` | One entry per application with open findings; not capped |
| `generated_at` | datetime | UTC |

### `RiskByApplicationItem`

| Field | Type | Notes |
|---|---|---|
| `application_id` | UUID | From `access_facts.application_id_denorm` |
| `risk_score` | int | Same formula as `top-risks`, summed across all subjects with access to this application |
| `open_findings_count` | int | Total open findings across all severities (equals `sum(severity_breakdown.values())`) |
| `severity_breakdown` | `dict[str, int]` | All five `SodSeverity` keys (`critical`, `high`, `medium`, `low`, `informational`); zero-filled for absent severities. `informational` is counted but contributes 0 to `risk_score`. |

### Sort order

`risk_score DESC`, then `application_id ASC`.

## `GET /api/v0/analytics/findings-summary`

Product-neutral digest of the current open `Finding` population.
Postgres-only — does not touch the lake. This is the payload the
Deterministic Report endpoint reuses verbatim under
`DeterministicReport.summary` (see
[Deterministic Report](deterministic-report.md)).

The summary does **not** include `risk_score` — it is a count-based
digest, not a scored ranking.

### Query parameters

| Name | Type | Default | Bounds | Effect |
|---|---|---|---|---|
| `top_n` | int | `10` | `1..100` | Caps `top_applications` and `top_subjects`. |
| `quick_wins_limit` | int | `50` | `1..500` | Caps `quick_wins`. |

Out-of-bounds values return 422.

### Response — `FindingsSummary`

| Field | Type | Notes |
|---|---|---|
| `total_findings` | int | Total open findings across all severities |
| `findings_by_severity` | `dict[str, int]` | All `SodSeverity` values present as keys (`critical`, `high`, `medium`, `low`, `informational`); zero-filled for absent severities |
| `findings_by_kind` | `dict[str, int]` | All `FindingKind` values present as keys (`sod`, `orphan_access`, `terminated_access`, `unused_access`, `privileged_access`); zero-filled for absent kinds |
| `critical_findings` | int | Convenience accessor — same as `findings_by_severity['critical']` |
| `high_findings` | int | Convenience accessor — same as `findings_by_severity['high']` |
| `top_applications` | `TopApplicationFindingCount[]` | Top-N applications by finding count |
| `top_subjects` | `TopSubjectFindingCount[]` | Top-N subjects by finding count |
| `quick_wins` | `QuickWinFinding[]` | High/critical findings eligible for quick remediation; see below |
| `generated_at` | datetime | UTC |

### `TopApplicationFindingCount`

| Field | Type | Notes |
|---|---|---|
| `application_id` | UUID | Resolved through `findings → ent_accounts → application_id` |
| `finding_count` | int | Open findings on accounts in this application |

Sort order: `finding_count DESC`, then `application_id ASC`.

Findings with `account_id IS NULL` are excluded from this list — a
subject-only finding cannot be attributed to a single application.
Such findings still count in `total_findings`, `findings_by_severity`,
and `findings_by_kind`.

### `TopSubjectFindingCount`

| Field | Type | Notes |
|---|---|---|
| `subject_id` | UUID | The subject the findings are anchored on |
| `finding_count` | int | Open findings whose `subject_id` matches |

Sort order: `finding_count DESC`, then `subject_id ASC`.

Only findings with `subject_id IS NOT NULL` are considered (in
particular, `orphan_access` findings — which by construction have no
subject — are excluded from this list).

### `QuickWinFinding`

A "quick win" is a finding the platform considers cheaply remediable:
the kind has a clear corrective action (revoke or review the access)
and the severity is high enough to justify the work now.

| Field | Type | Notes |
|---|---|---|
| `finding_id` | int | `Finding.id` |
| `kind` | string | One of the eligible kinds — see below |
| `severity` | string | `critical` or `high` only |
| `subject_id` | UUID \| null | May be null for `orphan_access` findings |
| `account_id` | UUID \| null | May be null for subject-only findings |
| `detected_at` | datetime | When the scan engine recorded the finding |

Eligibility — a finding qualifies if **all** of the following hold:

- `status = 'open'`
- `kind ∈ { orphan_access, terminated_access, unused_access }`
- `severity ∈ { critical, high }`

`sod` and `privileged_access` findings are intentionally excluded —
they typically need policy review, not a one-click revoke, so they do
not fit the "quick win" framing.

Sort order: `critical` before `high`, then `detected_at DESC`, then
`finding_id DESC`. Severity ordering is computed via a `CASE`
expression, not enum-declaration order, so it is robust to schema
edits.

The result is then capped at `quick_wins_limit`.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/analytics/top-risks` | Top-N (subject, application) pairs by risk score |
| `GET` | `/api/v0/analytics/risk-by-application` | Risk aggregated per application |
| `GET` | `/api/v0/analytics/findings-summary` | PG-only digest of current open findings |

All three endpoints are read-only. They emit one INFO log per call
under the `engines.access_analysis.analytics` component
(`top_risks_computed`, `risk_by_application_computed`, and
`findings_summary_computed` respectively) and emit no events.

## CLI

No CLI surface. The endpoints are consumed directly by REST clients.
