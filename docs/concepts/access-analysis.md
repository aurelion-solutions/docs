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

Segregation of Duties (SoD) is a higher-level policy concern: certain combinations of capabilities held by the same subject are forbidden (`create_vendor` + `approve_payment` is the canonical example). The SoD endpoints under `/api/v0/sod/*` are being built incrementally; the picture they will form looks like this:

```
Subject capabilities  ──┐
                        ├──→  SoD evaluator  ──→  Violations
Hypothetical sources ──→ resolver ──→ slugs ──┘
```

What ships today:

- **`POST /api/v0/sod/resolve-capabilities`** — the pre-flight slug resolver. Pure read, no persistence, no events.
- **`POST /api/v0/sod/evaluate`** — evaluate the current SoD posture for a subject against the active rule set, returning any `Violation`s. Pure read, no persistence, no events.
- **`POST /api/v0/sod/what-if`** — compose the resolver with the evaluator: given a subject and a hypothetical bundle of grants, return the SoD violations that *would* fire if the bundle were granted. Pure read, no persistence, no events. Closes the evaluator surface (`resolve-capabilities` + `evaluate` + `what-if`).
- **`POST /api/v0/scan-runs/{id}/run`** — execute a batch scan: the ScanEngine fans out to the SoD evaluator and to the orphan / terminated / unused-account detectors, persists results as `Finding` rows (deduplicated by `evidence_hash`, with existing mitigations relinked), and emits `access_analysis.scan.*` and `access_analysis.finding.*` events. This is the first write surface in `/sod` / `/scan-runs/*` — every other endpoint above is read-only.

## Where it lives

`src/capabilities/access_analysis/` — the Capabilities layer (Layer 2). The slice tree:

| Subslice | Purpose |
|---|---|
| `capabilities/` | `Capability` entity + scope keys |
| `capability_mappings/` | `CapabilityMapping` rule entity |
| `capability_grants/` | Projector + persisted projection rows |
| `services/` | Cross-slice services (resolver lives here) |
| `sod/` | HTTP surface for `/sod/*` endpoints |

Access Analysis depends on EAS and on its own subslices only. It does not import from any product (IGA, IDP) — products consume it, not the other way around.
