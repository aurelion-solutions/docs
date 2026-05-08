# Access Analysis

Access Analysis is the layer that turns the raw "who can do what on which resource" graph into a vocabulary the business understands — **capabilities** — and uses that vocabulary to reason about Segregation of Duties (SoD).

It sits between the Effective Access Store (EAS — the normalized current-state projection of access) and the higher-level governance products. It does not own the raw grants; it interprets them.

## Why capabilities exist

Raw access lives in two shapes that are unfit for business reasoning:

- **EAS rows** describe permissions in source-system vocabulary: "subject S has action `write` on resource `vendor_master/12`". Useful for audit, useless for asking "can this person create vendors?".
- **Native roles** are organization- and connector-specific. The same business meaning hides behind dozens of differently named roles across systems.

A **Capability** is a stable, business-named slug that abstracts both away: `create_vendor`, `approve_payment`, `release_invoice`. It is the only vocabulary that policies, SoD rules, and reports speak.

```
    Raw grants (EAS)             Business reasoning
    ─────────────────            ───────────────────
    write on vendor_master ─┐
    admin on vendors_role  ─┼──→  capability: create_vendor
    role: AP_VENDOR_EDIT   ─┘
```

One capability, many possible underlying grants. The mapping is explicit, configurable, and versioned.

## CapabilityMapping — the translation rule

A **CapabilityMapping** is a rule that says: "when an effective grant looks like X, it implies capability Y." Each mapping carries a set of matchers; a grant must satisfy every matcher present for the rule to fire.

The matchers form a three-stage funnel — most restrictive first, broadest last:

| Stage | Matcher | Meaning |
|---|---|---|
| 1 | `resource_id` | This exact resource row |
| 2 | `resource_kind` + `resource_path_glob` | A class of resources, optionally narrowed by an external-id pattern |
| 3 | `application_id` + `action_slug` | Any grant of that action in that application |

A mapping with only `application_id` + `action_slug` is the broadest; a mapping with a concrete `resource_id` is the most specific. Mappings are **additive** — overlapping rules just produce the same capability twice, which is collapsed downstream.

Mappings are stored as rows; deactivating a mapping (`is_active = false`) takes it out of the active vocabulary without losing its history. The same applies to capabilities themselves — an inactive capability is silently dropped from any output, even if mappings still point at it.

## Scope keys — capabilities are not always atomic

A capability often makes sense only in a **scope**: "approve_payment up to $50,000", "edit_vendor in cost center EU-NORTH". Scopes are not freeform strings; they are typed by a **CapabilityScopeKey** declared per capability (`amount_limit`, `cost_center`, `legal_entity`, …).

The scope value for a given grant is resolved from the underlying resource and subject attributes at projection time. Scope-aware features (notably the SoD evaluator in later phases) consume both the slug and the scope key/value pair.

The pre-flight resolver described below intentionally ignores scope values — it answers the slug question only.

## Two consumers, one matcher

The same matching logic feeds two very different code paths:

```
                   ┌──────────────────────────────────┐
                   │  matcher_applies(view, mapping)  │
                   │   (single source of truth)       │
                   └─────────────┬────────────────────┘
                                 │
              ┌──────────────────┴───────────────────┐
              ▼                                      ▼
   CapabilityProjector                    CapabilityResolverService
   (writer, event-driven)                 (read-only, on demand)
   EAS row → CapabilityGrant rows         Sources → list[slug]
```

Both consumers import the same `matcher_applies` function from the projector module. Drift between "what would be projected" and "what would be resolved" is impossible by construction.

## CapabilityProjector — the writer

The projector reacts to EAS changes. When an effective grant is created, updated, or tombstoned, the projector replays all active mappings against it and writes the resulting `CapabilityGrant` rows. These rows are the persisted projection that powers reports, dashboards, and the SoD evaluator.

Projection is event-driven and idempotent. It is one of two writers in the access-analysis tree; the other is the ScanEngine, which writes `Finding` rows on demand (see below).

## CapabilityResolverService — the pre-flight read

The resolver answers a deliberately narrower question: *given an arbitrary list of grants — real or hypothetical — which capability slugs would they imply?*

It exists for the use cases the projector cannot serve:

- **Request engine pre-flight.** Before granting access, ask "what capabilities is the requester about to acquire?"
- **Role design.** Compose a hypothetical bundle of grants and inspect the resulting capabilities before persisting anything.
- **What-if SoD.** Combine a subject's current capabilities with the resolver's output for a proposed bundle and feed the union into the SoD evaluator.

Inputs are `EffectiveGrantRef` values — caller-built, denormalized references to a grant. The resolver does **not** round-trip through the EAS table; the caller is free to invent grants that have no corresponding row. Subject identity, scope values, and tombstone state are all ignored — they are not part of the slug question.

Output is `sorted(set(slugs))`: alphabetical, distinct, and limited to capabilities that are currently active. Empty input is a valid input and returns `[]` — not an error.

The resolver is strictly read-only. It performs no flush, no commit, no event emission, and uses no log service. A contract test enforces this at the AST level.

## SoD flow — where this fits

Segregation of Duties (SoD) is a higher-level policy concern: certain combinations of capabilities held by the same subject are forbidden (`create_vendor` + `approve_payment` is the canonical example). The SoD endpoints under `/api/v0/sod/*` plus the capability-preview surface form this picture:

```
Subject capabilities  ──┐
                        ├──→  SoD evaluator  ──→  Violations
Hypothetical sources ──→ resolver ──→ slugs ──┘
```

What ships today:

- **`POST /api/v0/capability-preview/resolve`** — the pre-flight slug resolver. Pure read, no persistence, no events.
- **`POST /api/v0/sod/evaluate`** — evaluate the current SoD posture for a subject against the active rule set, returning any `Violation`s. Pure read, no persistence, no events.
- **`POST /api/v0/sod/what-if`** — compose the resolver with the evaluator: given a subject and a hypothetical bundle of grants, return the SoD violations that *would* fire if the bundle were granted. Pure read, no persistence, no events.
- **`POST /api/v0/scan-runs/{id}/run`** — execute a batch scan: the ScanEngine fans out to the relevant policy types (`sod`, `access_risk`, `lifecycle`) and the policy cartridges they ship, persists results as `Finding` rows (deduplicated by `evidence_hash`, with existing mitigations relinked), and emits `access_analysis.scan.*` and `access_analysis.finding.*` events. This is the first write surface in this area — every other endpoint above is read-only.

## Scan orchestration vs. policy evaluation

Access Analysis owns the *batch* question — "across this whole population, what is wrong right now?" — but it no longer owns the *atomic* question of whether a specific condition applies. That question belongs to the policy-assessment engine.

The split:

| Concern | Owner |
|---|---|
| Scan run lifecycle, scoping, fan-out, deduplication, finding persistence, mitigation relinking, event emission | Access Analysis |
| "Does this single subject / account / grant trip the rule?" — pure evaluator per policy cartridge, grouped under a policy type | Policy Assessment |

The non-SoD checks (`orphaned_access`, `unused_access`, `terminated_subject_access`) are file-based policy cartridges inside the `access_risk` and `lifecycle` policy types — not standalone policy types of their own. Access Analysis calls them through `PolicyCartridgeAssessmentService.evaluate_file(path, context)`; it does not implement them. See [Policy Cartridges](policy-cartridges.md) for the YAML schema and the DSL, and [Policy Decision Point — Policy types](policy-engine.md#policy-types) for the routing.

Concretely, `ScanEngine` builds a small context dict per candidate (`{'subject_not_found': bool}` for orphan, `{'subject': {'status': '...'}}` for terminated, `{'days_since_last_use': int}` for unused), passes it to the policy-cartridge service, and reads back a `PolicyAssessmentOutput`. The cartridge's `decision.risk_level` becomes the persisted finding's severity — the YAML is the source of truth for severity, not the engine code. The Python `DEFAULT_*_SEVERITY` constants act only as a fallback when the cartridge response carries no `Decision`.

SoD goes through a different path: it is **DB-backed** (rules persisted in `SodRule` rows) and evaluated by a pure Python evaluator under `policy_types/sod/`. SoD is intentionally not expressed as a policy cartridge — see [Policy Decision Point — SoD stays DB-backed](policy-engine.md#sod-stays-db-backed).

## Analytics surface

Once findings exist, three read-only analytics endpoints answer the
"what does the population currently look like?" question without
re-running any scan:

```
GET /api/v0/analytics/top-risks               →  ranked (subject, app) pairs
GET /api/v0/analytics/risk-by-application     →  ranked applications
GET /api/v0/analytics/findings-summary        →  count-based digest
```

The first two return a `risk_score`. The score is an MVP aggregation —
`Σ(severity_weight × open_findings_in_severity)` with weights
`critical=100, high=50, medium=20, low=5` — and is intentionally **not** the canonical Aurelion risk model. It is good enough to rank the worst-offending subjects and applications today; it has the known limitation that 100 `low` findings outweigh one `critical`, and it must not be surfaced as "the" risk score in customer-facing reports. The canonical model is a future-phase concern. The two scored endpoints are computed in DuckDB over `normalized.access_facts` joined with the Postgres `findings` table; the lake is queried in-place via `iceberg_scan` and `kernel_pg.findings`, so analytics never duplicates PG data into the warehouse.

The third endpoint, `findings-summary`, is Postgres-only and does **not** include a risk score. It returns totals, breakdowns by severity and by kind, top applications and top subjects, and a `quick_wins` list — high/critical findings of kinds with a clear corrective action (`orphan_access`, `terminated_access`, `unused_access`). `sod` and `privileged_access` are intentionally excluded from quick wins because they typically require policy review rather than a one-click revoke.

`findings-summary` is consumed twice. Once directly by clients that want a digest of current findings; and a second time inside the deterministic-report payload below — `DeterministicReport.summary` is the verbatim `FindingsSummary` envelope. Treat `findings-summary` as the canonical count-based digest of open findings; the deterministic report wraps it with `top_findings`, `recommendations`, and the five `executive_summary` blocks, and contains no separately-computed counts.

Field-level details, query parameters, sort orders, and the severity-weight table live in [Analytics (reference)](../reference/analytics.md).

## Deterministic report payload

Once findings are persisted, downstream consumers — the Lens AI summary, future renderers (CLI, Studio, IGA, PDF generator) — need a stable structured input shape over kernel data. The `reports/` sub-slice of `access_analysis` provides exactly that:

```
GET /api/v0/reports/deterministic  →  DeterministicReport
```

The envelope composes the existing `FindingsSummary` (counts, breakdowns, top apps/subjects, quick wins) with three additional pieces: `top_findings` for the open `critical`/`high` population with denormalized evidence, `recommendations` derived from a fixed rule table over `FindingKind` × severity floor, and exactly five `executive_summary` blocks in a load-bearing order (`posture_overview`, `top_risks`, `quick_wins_overview`, `application_hotspots`, `subject_hotspots`).

The endpoint is intentionally narrow: no LLM, no PDF or HTML rendering, no scan-run scope, no date-range filter, no per-application variant. The payload is global over currently open findings. AI summarises this payload — it does not produce findings, recommendations, or executive metrics. Field-level details and the recommendation rule table live in [Deterministic Report (reference)](../reference/deterministic-report.md).

The end-to-end loop, with Lens as the first consumer, looks like this:

```
  kernel /reports/deterministic   ──>  Lens server-side page
                                          │
                                          │ DeterministicReport
                                          ▼
                                   Lens SSE route (server-side)
                                          │
                                          │ buildSummaryPrompt(report)
                                          ▼
                                   { system, user } messages
                                          │
                                          ▼
  kernel /inference/stream  <─────  same correlation_id
          │
          │ SSE token stream
          ▼
        browser
```

Two architectural properties fall out of this shape:

- **The browser never composes the LLM prompt.** Lens' SSE route handler accepts only the deterministic report payload (or the session id needed to fetch it server-side); it constructs the `system` and `user` messages itself before calling kernel inference. The route rejects any body carrying a `messages` field. This is a security boundary — a compromised browser cannot inject arbitrary prompts into the platform LLM surface, only fabricate values inside the report shape, which the model treats as data.
- **The platform stays prompt-template-free.** Consistent with the rule in [LLM Platform Layer — Determinism and bounded surface](llm-platform.md#determinism-and-bounded-surface), the prompt template lives in the consumer (here, Lens), not in `platform/llm/`. The kernel transports tokens; it does not own the report-summary framing.

## Where it lives

Access Analysis is an engine in Layer 2 (Engines). It owns:

| Concern | What it does |
|---|---|
| Capability projection | Replays active mappings against EAS changes and writes `CapabilityGrant` rows |
| Capability resolver (read-only) | Answers the pre-flight slug question without touching the EAS table |
| Capability preview surface | The HTTP entry point for the resolver (canonical: `/capability-preview/resolve`) |
| Assessment-preview surface | Small read-only HTTP surface for inspecting what a scan would find before running it |
| SoD endpoints | `/sod/evaluate` and `/sod/what-if` |
| Scan orchestration | Scan run lifecycle, fan-out to policy types, finding persistence, mitigation relinking, event emission |
| Analytics surface | Read-only aggregations over open findings: `/analytics/top-risks`, `/analytics/risk-by-application`, `/analytics/findings-summary` |
| Deterministic report payload | Read-only envelope over open findings consumed by Lens AI and future renderers (canonical: `/reports/deterministic`) |

The `Capability`, `CapabilityMapping`, and `CapabilityGrant` ORM tables themselves are owned by Inventory — the engine operates on top of those tables, it does not own them.

Access Analysis depends on EAS and Inventory only. It does not import from any product (IGA, IDP) — products consume it, not the other way around.
