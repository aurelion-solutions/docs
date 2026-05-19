# Deterministic Report

Product-neutral structured payload built from access-analysis findings.
The endpoint is read-only. It does not render PDF or HTML, it does not
call an LLM, and it does not invent data — every value is derived
deterministically from current open `Finding` rows.

The payload is the deterministic input for downstream renderers: AI
summary services, CLI report generators, IDE integrations, and any
client that wants a stable shape over kernel findings without
duplicating the SQL.

For the conceptual role of this surface inside the access-analysis
engine, see
[Access Analysis — Deterministic report payload](../concepts/access-analysis.md#deterministic-report-payload).

## Envelope

`GET /api/v0/reports/deterministic` returns a single `DeterministicReport`
envelope. There is no per-application or per-scan-run variant — the
payload is global over all currently open findings.

| Field | Type | Notes |
|---|---|---|
| `summary` | `FindingsSummary` | Reused payload from `GET /api/v0/analytics/findings-summary`. Totals, breakdowns by severity and kind, top applications, top subjects, quick wins. |
| `top_findings` | `TopFinding[]` | Open findings with severity `critical` or `high`, ordered critical-first then by `detected_at DESC, id DESC`, capped at `top_findings_limit`. |
| `recommendations` | `Recommendation[]` | Rule-based, one entry per `FindingKind` whose open population meets the configured severity floor. |
| `executive_summary` | `ExecutiveSummaryBlock[]` | Always exactly five blocks in fixed order. |
| `generated_at` | datetime | UTC. Stamped at the end of payload assembly; not the same value as `summary.generated_at`. |

### TopFinding

| Field | Type | Notes |
|---|---|---|
| `finding_id` | int | `Finding.id` |
| `kind` | string | `FindingKind` value |
| `severity` | string | `critical` or `high` (the route filters lower severities out) |
| `subject_id` | UUID \| null | May be null for findings anchored only on an account |
| `account_id` | UUID \| null | May be null for subject-scoped findings |
| `detected_at` | datetime | When the scan engine recorded the finding |
| `evidence` | `EvidenceSnippet` | Denormalized join data; see below |

### EvidenceSnippet

Resolved by left-joining `findings → ent_subjects` and
`findings → ent_accounts → applications`. Any column missing because the
finding has no `subject_id` or no `account_id` stays `null`.

| Field | Type | Notes |
|---|---|---|
| `subject_external_id` | string \| null | From `ent_subjects.external_id` |
| `account_username` | string \| null | From `ent_accounts.username` |
| `application_id` | UUID \| null | From `ent_accounts.application_id` (a `Finding` has no direct `application_id`) |
| `application_code` | string \| null | From `applications.code` |

### Recommendation

| Field | Type | Notes |
|---|---|---|
| `kind` | string | One of `revoke_orphan_access`, `revoke_terminated_access`, `review_unused_access`, `review_privileged_access`, `review_sod_violation` |
| `finding_kind` | string | The `FindingKind` this recommendation is derived from |
| `severity_floor` | string | Plain string in `{low, medium, high, critical}`. The recommendation fires only if at least one open finding of `finding_kind` reaches this floor. |
| `affected_finding_count` | int | Total open findings of `finding_kind`, regardless of severity |
| `text` | string | Short English template with the count interpolated. Deterministic — no LLM. |

Sort order: `severity_floor` priority (`critical < high < medium < low`),
then `affected_finding_count DESC`, then `kind` ascending.

Rule table:

| `finding_kind` | `kind` | `severity_floor` |
|---|---|---|
| `orphan_access` | `revoke_orphan_access` | `high` |
| `terminated_access` | `revoke_terminated_access` | `high` |
| `unused_access` | `review_unused_access` | `medium` |
| `privileged_access` | `review_privileged_access` | `high` |
| `sod` | `review_sod_violation` | `high` |

### ExecutiveSummaryBlock

Five blocks in a fixed, load-bearing order. Block ids and order are
stable — downstream AI prompts and renderer UIs both rely on positional
reads.

| Position | `block_id` | Title | `metric` |
|---|---|---|---|
| 1 | `posture_overview` | Posture Overview | `summary.total_findings` |
| 2 | `top_risks` | Top Risks | `len(top_findings)` |
| 3 | `quick_wins_overview` | Quick Wins | `len(summary.quick_wins)` |
| 4 | `application_hotspots` | Application Hotspots | `summary.top_applications[0].finding_count` or `null` |
| 5 | `subject_hotspots` | Subject Hotspots | `summary.top_subjects[0].finding_count` or `null` |

`body` is a deterministic English template with numeric anchors only.
All five blocks are always present, even when their metric is `0` or
`null`.

## Query parameters

| Name | Type | Default | Bounds | Effect |
|---|---|---|---|---|
| `top_findings_limit` | int | `20` | `1..100` | Caps `top_findings`. Out-of-bounds → 422. |
| `summary_top_n` | int | `10` | `1..100` | Forwarded to `findings-summary` for `top_applications` / `top_subjects` size. |
| `summary_quick_wins_limit` | int | `50` | `1..500` | Forwarded to `findings-summary` for the `quick_wins` cap. |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/reports/deterministic` | Build and return a `DeterministicReport` envelope |

Read-only. No events, no mutations, no scan-run scope, no date filter.
Two log records are emitted per call: one from the inner
`AnalyticsService.get_findings_summary`
(`engines.access_analysis.analytics.findings_summary_computed`) and one
from the payload service itself
(`engines.access_analysis.reports.deterministic_report_computed`).

## CLI

No CLI surface. The endpoint is consumed by REST clients directly.
