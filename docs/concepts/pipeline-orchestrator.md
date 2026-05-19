# Pipeline Orchestrator

The pipeline orchestrator is a kernel-native primitive for running
YAML-defined, multi-step workflows inside Aurelion. It exists so that
recurring cross-engine sequences — reconciliation followed by policy
assessment followed by report generation, for example — can be declared
once and executed by the platform itself, without an external scheduler
(Airflow, Dagster, Temporal) and without bespoke per-feature glue code.

## Why it is part of the platform

Aurelion already owns the data, the connectors, the secrets, and the
events. Outsourcing orchestration to a separate system would mean
duplicating identity, duplicating credentials, and pushing pipeline
state outside the same database that holds the domain it operates on.
The orchestrator is therefore a Layer-0 platform primitive, alongside
the database, the message queue, and the logs subsystem.

## Not to be confused with access_plan

There are two things in the codebase that sound like "orchestrator" or
"plan". They are unrelated:

- **`platform/orchestrator/`** — the generic, YAML-driven pipeline
  engine described on this page. Knows nothing about identity.
- **`engines/access_plan/`** — an IGA-domain engine that diffs
  desired vs current access and produces an immutable plan of
  operations. Knows nothing about pipelines. See
  [Declarative Access Planning](access-planning.md).

The first is a platform primitive. The second is a capability engine
that happens to live one layer up and may itself be invoked from a
pipeline step.

## Three layers of ownership

A running pipeline involves three distinct concerns, each owned by a
different place in the codebase:

```
  Pipeline YAML  ──────  describes the workflow
       │                 (steps, args, triggers)
       ▼
  Orchestrator   ──────  owns run state
  (platform)             (PipelineRun, StepRun)
       │
       ▼
  Engine action  ──────  does the actual work
  (engines/*)            (registered via @register_action)
```

| Concern | Owned by |
|---|---|
| Pipeline definitions | `aurelion-kernel/pipelines/*.yaml` |
| Run and step state | `platform/orchestrator/` (sole writer) |
| Action implementations | engine slices, via `@register_action` |

This separation is a hard invariant. Engine actions never write to
`pipeline_runs` or `step_runs`; the orchestrator never knows what an
action does internally. The contract between them is the action
registry plus a per-step `ActionContext`.

## The runtime

Pipelines do not run inside the platform API. They run in a separate
process — `platform_executor_node` — that polls Postgres for pending
runs and dispatches their steps. The executor is horizontally
scalable: multiple instances compete for work using
`FOR UPDATE SKIP LOCKED`, so two workers cannot claim the same run.

The executor is a single-slot worker. While a step is running, it
refreshes `pipeline_runs.last_heartbeat_at` every 3 seconds so the
reclaim sweep can distinguish dead workers from live ones. The
executor also parks `wait_for_event` steps — the run transitions to
`awaiting_event`, the slot is released, and the matcher resumes the
run when a matching event arrives; see [Event Flow](event-flow.md)
for the mechanics. The executor supports graceful drain, reclaim,
and a two-layer heartbeat model. Multi-slot concurrency and HTTP
health endpoints (`/healthz`, `/readyz`, `/metrics`) are not yet
implemented.

For the runtime contract — start command, environment variables,
deployment topology — see the operations page once it lands. For the
internal session protocol and SQL details, read the docstrings in
`src/platform/orchestrator/runner.py`.

## See also

- [Idempotency and Reclaim](idempotency-and-reclaim.md) — why every
  engine action must be idempotent and how the reclaim sweep relies
  on that contract
- [Heartbeat Architecture](heartbeat-architecture.md) — the two-layer
  heartbeat model and design trade-offs
- [Event Flow](event-flow.md) — how the orchestrator uses
  `aurelion.events` as both emitter and consumer
- [Pipeline YAML](../reference/pipeline-yaml.md) — step types,
  triggers, and the full grammar reference
- [Pipeline Runs API](../reference/pipeline-runs-api.md) — REST
  endpoints, data model, and idempotency strategy
