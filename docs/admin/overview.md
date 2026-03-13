# Administration Overview

This section covers platform administration: managing identities, applications, connectors, and access state. Most admin operations go through the REST API or CLI — there is no dedicated admin UI yet.

## Identity management

**Employees and persons** are created via `POST /api/v0/persons` + `POST /api/v0/employees`, or ingested from source systems via connectors. To lock an employee (block all access without deletion), set `is_locked: true` via `PATCH /api/v0/employees/{id}`. Locked employees receive a `deny` from the PDP regardless of their access facts.

**NHIs** are managed via `POST /api/v0/nhis`. Each NHI should have an owner employee assigned (`owner_employee_id`) for accountability.

**Subjects** are created automatically when the underlying identity is created. Status transitions (active → suspended → terminated) are managed via `PATCH /api/v0/subjects/{id}`.

## Application and connector management

Register a new integration with `al app create --name <name> --code <code>`. The `code` is the stable identifier used by the Policy Decision Point — choose it carefully.

To disable an application without deleting it, set `is_active: false` via `PATCH /api/v0/applications/{id}`. Inactive applications are excluded from reconciliation and provisioning.

Connector instances register themselves on startup. Monitor their status with `al app connectors list`. If no instance is online for an application's required tags, reconciliation will fail.

## Access state management

Access state is maintained by the reconciliation engine. To force a full sync for an application:

```bash
al reconciliation run --application-id <uuid>
```

To inspect what access currently exists for a subject:

```bash
al inventory access-facts list --subject <subject-uuid>
```

## Secrets

Platform secrets (connector credentials, provider tokens) are managed via the secrets subsystem. Add a secret:

```bash
al secrets create --key connector/github --provider file --namespace default --value ghp_xxx
```

Secrets are referenced by key in application config and connector payloads. Values are never returned in list responses — only via direct `get`.

## Logs and monitoring

Operational logs are buffered in the log buffer and can be read:

```bash
al logs read --limit 100
```

For production, configure a SIEM provider (Splunk, ELK, etc.) via the secret providers API and run the `mq_log_siem_consumer` runtime — it forwards the `aurelion.logs` exchange to your SIEM.

## Runtimes

All background runtimes must be running for full platform functionality. See [Operations](../operations/overview.md) for the full list and startup instructions.
