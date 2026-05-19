# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Notifications engine and platform channels documented across all four Diátaxis quadrants.**
  - `concepts/notifications.md` — engine/platform split, template model, four delivery channels (email / sms / webhook / inapp), provider resolution.
  - `reference/notifications.md` — `notifications.send_*` engine actions + per-channel `Provider` Protocol + `Message` / `SendResult` dataclasses + template catalogue.
  - `operations/notifications.md` — env vars (`AURELION_NOTIFICATIONS_<CHANNEL>_PROVIDER`), required kernel-secret keys per provider, per-provider failure modes.
- **`reference/storage-providers.md`** — `DataLakeStorage` Protocol, built-in `file` / `s3` / `iceberg` providers (the last two declared "not implemented"), `--storage-provider` CLI contract.
- **`reference/effective-grants.md`** — Effective Access Store read API: `list_grants`, `explain_access`, `get_grant` REST endpoints + `effective_access.list_grants`, `explain_access`, `get_grant`, `project_access_fact`, `project_application`, `apply_incremental_change` engine actions.
- **`concepts/domain-slice-pattern.md`** — `models.py` / `schemas.py` / `service.py` / `routes.py` slice anatomy + layer-routing rules + "only `service.py` emits events" invariant. Previously lived only in internal planning docs.
- **`operations/message-queue.md`** — MQ exchange topology: `aurelion.events`, `aurelion.logs`, `aurelion.logs.buffer`, `aurelion.logs.siem` + connector commands / responses / registry exchanges + queue declaration ownership + routing-key conventions.
- **`cli/events.md`** — `al events tail` (the only CLI command that reads the ring-buffer events stream).
- **`cli/policy.md`** — `al policy evaluate` (file / stdin input, decision shape, exit codes).
- **`mkdocs.yml` nav** — new pages slotted into `Concepts` (Domain Slice Pattern, Notifications), `Reference → Access` (Effective Grant), `Reference → Platform` (Storage Providers, Notifications), `Reference → CLI` (Events, Policy), `Operations` (Message Queue Topology, Notifications).

### Changed

- **`api/overview.md`** — explicit "REST only (no GraphQL)" constraint section + Authentication section updated to "not implemented" (was a stale forward-looking claim).
- **`concepts/events.md`** — `## Read API` section added (`GET /api/v0/platform/events` ring-buffer contract).
- **`reference/logs.md`** — `al logs tail` and `al logs buffer` CLI commands added alongside `read`; per-endpoint REST mapping (`/api/v0/platform/logs`, `/api/v0/log-buffer`).
- **`reference/secrets.md`** — provider routes corrected to `/api/v0/secrets/providers/...`.
- **`reference/engine-action-registry.md`** — four `notifications.send_*` actions added to the registered-action catalogue.
- **`reference/resources.md`** — CLI section aligned with actual `al inventory resources` flag set (was outdated).
- **`concepts/policy-cartridges.md`** — disclaimer "It is not a product name" removed; the `cartridges/<namespace>/` convention now honestly describes `<namespace>` as a product/domain owner, with `lens/` named as one such namespace.
- **`concepts/layers.md`** — ASCII layer pyramid box rewidened so the longest engine row (`inventory_reconcile · ingest · access_apply`) no longer overflows the right border.
- **`reference/org-units.md`** — `parent_id` field on `OrgUnitListItem` response shape (M-D); edit endpoint shown as `PATCH /v0/inventory/org-units/{id}` (was `PUT`), matching M-B.
- **Nine pages cleaned of `Lens` / `Journey` / `Pulse` product names.** Replaced with neutral platform terms (`REST clients`, `downstream renderers`, `product-layer policies`, `operator UI`): `concepts/access-analysis.md`, `concepts/identity-model.md`, `reference/persons.md`, `reference/employees.md`, `reference/org-units.md`, `reference/deterministic-report.md`, `reference/analytics.md`, `reference/policy-catalog.md`, `operations/access-plan.md`. Engineering Studio is kept where it appears — it is an IDE tool, not a Layer-3 product.

### Removed

- **Product-layer documentation pages.** `docs/user/journey/overview.md` and `docs/guides/journey/contractor-companies.md` deleted along with their empty parent directories. The `Aurelion Journey` block is removed from `mkdocs.yml` nav. Platform docs describe the platform; product-layer UX belongs in the product repo.

## [0.8.0] - 2026-05-13

### Added

- Phase 19 Access Plan Engine documentation complete
- `docs/concepts/access-planning.md` — new Concepts page: declarative planning model, diff/DAG engine, initiative lifecycle, multi-transport invocation
- `docs/operations/access-plan.md` — operator runbook: plan lifecycle, status values, invalidation_reason semantics, requires_confirmation, dry-run, lease diagnosis, stuck execution triage
- `docs/reference/access-plan-api.md` — REST contract: all 5 access-plan endpoints, request/response shapes, 409 codes, error shape, event semantics
- `docs/reference/connector-descriptor.md` — connector descriptor reference: dependency_rules, cross-app deps, account_status.transitions, cascades.before_disable, verify_fact_supported, supported_fact_kinds
- `docs/reference/access-apply.md` — access-apply engine reference: execute_plan action, F3 chain, lease semantics, restart recovery

### Changed

- `mkdocs.yml` nav updated with Phase 19 pages (concepts, operations, reference sections)
- Engine rename updates across docs: `reconciliation` → `inventory_reconcile`, `sync_apply` → `inventory_sync`, `effective_access` → `access_effective`, `provisioning` → `access_apply`
- `docs/concepts/reconciliation.md`, `docs/reference/reconciliation.md`, `docs/guides/run-reconciliation.md` updated for `inventory_reconcile` rename
- `docs/reference/provisioning.md` updated for `access_apply` rename
- Various concept and reference pages updated to reflect Phase 19 engine architecture

## [0.5.0] - 2026-05-12

### Added

- Phase 18 Native Pipeline Orchestrator documentation complete
- `docs/tutorials/write-your-first-pipeline.md` — new Tutorial page (Diátaxis Tutorial quadrant): linear walkthrough for writing a two-step `orphan_check` pipeline, restarting the kernel, verifying load via `al pipelines list/show`, triggering a run with `al pipelines run`, inspecting completion with `al pipelines runs get`, and reading the `pipeline.run.completed` event via `curl | jq`
- `mkdocs.yml` nav: new top-level `Tutorials:` section between `Home:` and `Concepts:` with one entry (`Write your first pipeline`)
- `docs/guides/cancel-pipeline-run.md` — new How-to guide: cancel a pipeline run via CLI and REST; per-status outcome table; verify via GET + event bus
- `docs/guides/retry-failed-run.md` — new How-to guide: retry a failed/cancelled run; when to retry vs not; what carries over; retry vs reclaim distinction
- `docs/guides/add-engine-action.md` — new How-to guide: 7-step walkthrough for registering a new engine action (Pydantic schemas, async function, decorator, idempotency decision, bootstrap import, tests, YAML usage)
- `docs/guides/wait-for-external-event.md` — new How-to guide: declare a `wait_for_event` step; how matching and timeout work; verify parked run; fire an ad-hoc event for testing
- `docs/guides/troubleshoot-stuck-runs.md` — new How-to guide: symptom-to-cause decision table; inspect run and steps; executor liveness; beat/matcher checks; next-action decision tree
- `docs/concepts/idempotency-and-reclaim.md` — new Concepts page: at-least-once execution problem, the idempotency contract, three implementation patterns (lake-level dedup, status-guarded UPDATE, trigger-level dedup), reclaim summary, and trigger idempotency as a separate concern
- `docs/concepts/heartbeat-architecture.md` — new Concepts page: two-layer heartbeat model (DB work-claim vs MQ liveness), trade-offs vs SKIP LOCKED only and vs ZooKeeper/etcd/Redis, beat and matcher advisory locks
- `docs/concepts/event-flow.md` — new Concepts page: orchestrator as emitter and consumer, MQ triggers, wait_for_event waiters, direct-emit vs outbox trade-off, correlation
- `docs/concepts/pipeline-orchestrator.md` — executor runtime concept page: bootstrap flow, work-loop semantics, three-session protocol, and explicit deferrals to Step 12b
- `docs/reference/connector-results.md` — `connector.result.received` event contract: payload shape, routing key, emission conditions, and ghost-event (pre-commit) caveat
- `docs/reference/pipeline-yaml.md` — Pipeline YAML grammar reference: top-level shape, triggers (MQ + schedule), steps (engine_call + wait_for_event), templating, matcher semantics, application_sync worked example
- `docs/reference/pipeline-runs-api.md` — Pipeline Runs REST API reference: data model, all 10 endpoints (verb/path/status codes), idempotency strategy, well-known discovery, error shape, CLI pointer
- `docs/reference/engine-action-registry.md` — Engine Action Registry reference: `@register_action` decorator, `ActionContext` fields, Pydantic contract, dotted naming, exceptions, registered-action catalogue
- `docs/reference/pipeline-events.md` — Pipeline Events catalogue: run-level and step-level routing keys, waiter resolution, executor liveness heartbeat, connector cross-reference
- `docs/reference/runtime-settings.md` — Runtime Settings reference: database-backed runtime keys, executor bootstrap env vars (`EXECUTOR_HEARTBEAT_SECONDS`, `EXECUTOR_DRAIN_TIMEOUT_SECONDS`)

### Changed

- `docs/concepts/pipeline-orchestrator.md` — stale forward-looking sentence rewritten to reflect shipped features (drain, parking, reclaim) vs deferred (multi-slot, health endpoints); `wait_for_event` parking note added; `## See also` block added with links to new concepts pages and reference pages
- `docs/reference/pipelines.md` split into four focused pages (`pipeline-yaml.md`, `pipeline-runs-api.md`, `engine-action-registry.md`, `pipeline-events.md`); original file deleted

### Removed

- `docs/reference/lake-migrations.md` deleted — `engines/lake_migration` slice retired in kernel Phase 17 Step 13.
- `docs/operations/lake-migration-runbook.md` deleted — operational runbook for the retired migration tool.
- `docs/cli/lake.md` rewritten to drop `migrate-from-pg` section; `status` and `compact` sections retained.
- `docs/concepts/layers.md` no longer lists `lake_migration` as an active engine.

## [0.4.0] - 2026-04-28

### Added

- Data Lake reference: `docs/reference/data-lake.md` — Iceberg + DuckDB architecture, lake tables, batch lifecycle
- Lake migrations reference: `docs/reference/lake-migrations.md` — migration strategy, rollback, schema evolution
- CLI lake commands: `docs/cli/lake.md` — `al datalake batches list`, status filtering, pagination
- Lake migration runbook: `docs/operations/lake-migration-runbook.md` — operational steps for Iceberg + DuckDB setup

### Changed

- `docs/reference/access-artifacts.md` — updated to reflect Iceberg storage (was PostgreSQL)
- `docs/reference/access-facts.md` — updated storage backend reference
- `docs/reference/artifact-bindings.md` — updated lake reference semantics
- `docs/reference/reconciliation.md` — expanded: DuckDB query patterns, lake-backed reconciliation flow
- `docs/concepts/events.md` — lake-related events added
- `docs/concepts/reconciliation.md` — lake integration notes
- `docs/guides/run-reconciliation.md` — updated for lake-backed artifact ingestion
- `docs/api/overview.md` — `/api/v0/datalake/batches` endpoint documented
- `docs/operations/overview.md` — lake operations section added
- `docs/operations/platform-api.md` — DuckDB/Iceberg health checks
- `mkdocs.yml` — new pages registered

## [0.3.0] - 2026-04-26

### Added

- `al sod apply` documented in `docs/cli/access-analysis.md` — YAML/JSON format, idempotency semantics, `min_count` explanation, `--dry-run` flag, example output

## [0.2.0] - 2026-04-25

### Added

- Access Analysis concept page (`docs/concepts/access-analysis.md`) — analysis model, findings lifecycle, SoD violation severity
- CLI reference for access analysis (`docs/cli/access-analysis.md`) — full command surface, SoD rule YAML format, dry-run flag

## [0.1.0] - 2026-04-24

### Added

- Initial documentation site with MkDocs
- Concepts: Platform Layers, Identity Model, Access Model, Normalization, Reconciliation, Policy Decision Point, Events and Logs
- Guides: Connect an application, Run reconciliation, Onboard an employee, Evaluate a policy decision
- Reference: complete reference for all domain entities — identity (Person, Employee, NHI, Subject), access (Account, Resource, Action, Artifact, Fact, Binding), governance (Initiative, Ownership, Usage, Threat), platform (Application, Connector, Reconciliation, Provisioning)
- Operations: platform API runbook, log buffer cleanup, MQ consumer configuration
- Admin overview

### Removed

- Old architecture docs structure (deprecated `architecture/endpoints/` and `architecture/entitlements/` pages)
