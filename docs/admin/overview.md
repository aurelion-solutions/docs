# Administration Overview

This page is a navigation hub for platform administration tasks. There is
no dedicated admin UI yet — every operation is exposed through the REST
API and the CLI.

## Common tasks

| Task | Entry point | Reference |
|---|---|---|
| Create a person | `POST /api/v0/persons` | [Person](../reference/persons.md) |
| Create an employee | `POST /api/v0/employees` | [Employee](../reference/employees.md) |
| Lock an employee | `PATCH /api/v0/employees/{id}` with `is_locked: true` | [Employee](../reference/employees.md) |
| Create an NHI | `POST /api/v0/nhis` | [NHI](../reference/nhi.md) |
| Change subject status | `PATCH /api/v0/subjects/{id}` | [Subject](../reference/subjects.md) |
| Register an application | `al app create` | [Application](../reference/applications.md) |
| Disable an application | `PATCH /api/v0/applications/{id}` with `is_active: false` | [Application](../reference/applications.md) |
| Inspect connector status | `al app connectors list` | [Connector Instance](../reference/connectors.md) |
| Trigger a reconciliation | `al reconciliation run --application-id <uuid>` | [Reconciliation](../reference/reconciliation.md) |
| Inspect access for a subject | `al inventory access-facts list --subject <uuid>` | [Access Fact](../reference/access-facts.md) |
| Manage platform secrets | `al secrets create` / `get` / `list` | [Secrets](../reference/secrets.md) |
| Read operational logs | `al logs read` | [Logs](../reference/logs.md) |
| Register an LLM model | `POST /api/v0/llm/models` | [LLM Model](../reference/llm-model.md), [Register an LLM model guide](../guides/register-llm-model.md) |
| Add a policy cartridge | edit `cartridges/lens/<policy_type>/*.yaml` | [Policy Cartridge Operations runbook](../operations/policy-cartridge-operations.md), [Add a policy cartridge guide](../guides/add-policy-cartridge.md) |

## Identity model

Two distinct entity families:

- **Human identities** — `Person` (the durable individual record) plus `Employee` (the employment relationship). See [Identity Model concept](../concepts/identity-model.md).
- **Non-human identities (NHI)** — service accounts, bots, system principals. Always own an `owner_employee_id` for accountability.

`Subject` is a unifying handle that both kinds project into; it carries the lifecycle status that the PDP reads.

## Access state

Access facts are written by the reconciliation engine, not by hand.
Manual mutation of `access_facts` is not supported — to change what an
account can do, change the upstream artifact and run a reconciliation.

For the full lifecycle of an access fact, see the [Access Model concept](../concepts/access-model.md)
and the [Reconciliation concept](../concepts/reconciliation.md).

## Logs and monitoring

For production, run the `mq_log_siem_consumer` runtime to forward the
`aurelion.logs` exchange to a SIEM (Splunk, ELK, etc.). For ad-hoc
inspection, use the log-buffer API or `al logs read`.

## Runtimes

All background runtimes must be running for full platform functionality.
See [Operations overview](../operations/overview.md) for the full list and
startup instructions.
