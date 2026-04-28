# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
