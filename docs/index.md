# Aurelion Documentation

Aurelion is an identity governance and access platform with a kernel
(Python/FastAPI), a VS Code extension (Engineering Studio), and a CLI.
This documentation covers all three.

## Where to start

| If you want to… | Start here |
|---|---|
| Understand the architecture | [Platform Layers](concepts/layers.md) |
| Understand the identity model | [Identity Model](concepts/identity-model.md) |
| Understand how access is normalized | [Access Model](concepts/access-model.md) |
| Connect a new application | [Connect an application](guides/connect-application.md) |
| Run a reconciliation | [Run reconciliation](guides/run-reconciliation.md) |
| Onboard an employee | [Onboard an employee](guides/onboard-employee.md) |
| Evaluate a policy decision | [Evaluate a policy decision](guides/evaluate-policy.md) |
| Add a policy cartridge | [Add a policy cartridge](guides/add-policy-cartridge.md) |
| Register an LLM model | [Register an LLM model](guides/register-llm-model.md) |
| Look up a REST entity | the [Reference](reference/persons.md) section |
| Run a deployment | [Operations overview](operations/overview.md) |

## Documentation layout

The site follows the [Diátaxis](https://diataxis.fr/) structure:

- **[Concepts](concepts/layers.md)** — explanations of the architecture, the identity model, the access pipeline, the policy engine, the policy cartridge system, the LLM platform, and the events bus. Read these to build a mental model.
- **[Guides](guides/connect-application.md)** — step-by-step procedures for common tasks. Read these when you have a specific goal.
- **[Reference](reference/persons.md)** — exhaustive entity, API, and CLI documentation. Read these to look up a field, an endpoint, or a flag.
- **[Operations](operations/overview.md)** — runbooks and runtime documentation for deploying, monitoring, and recovering Aurelion in production.

## Scope of this documentation

This site documents three components:

- **aurelion-kernel** — the Python/FastAPI backend (REST API, database, event bus, projection runtimes).
- **aurelion-engineering-studio** — the VS Code extension that browses platform state from the IDE.
- **aurelion-cli** — the `al` Typer client used in scripts and runbooks.

Adjacent products (IGA, IDP, ITDR, etc.) are documented separately.
