# Platform Layers

Aurelion is built as a three-layer pyramid. Layers define what each part owns and who can call whom. Dependencies flow downward only — upper layers know about lower ones, never the reverse.

```
┌─────────────────────────────────────────┐
│  Engines (Layer 2)                      │  engines and orchestrators
│  reconciliation · ingest · provisioning │
│  effective_access · policy_assessment   │
│  access_analysis · access_orchestration │
├─────────────────────────────────────────┤
│  Inventory (Layer 1)                    │  domain data and its API
│  persons · accounts · access facts ...  │
│  access_model · policy · assessment     │
├─────────────────────────────────────────┤
│  Platform (Layer 0)                     │  infrastructure
│  connectors · logs · secrets · DB · llm │
└─────────────────────────────────────────┘
```

## Platform

The infrastructure layer. It knows nothing about your employees or access rights — it knows about connections, logs, and the database.

This is where the connector instance registry, RabbitMQ clients, secret provider, data lake storage factory, the LLM platform (`platform/llm` — providers, clients, embeddings, RAG infrastructure), and logging live. If a component is needed by all other layers and has no domain meaning, it belongs in Platform.

## Inventory

The primary source of truth for domain data. Everything Aurelion stores long-term lives here: people, NHIs, accounts, resources, access facts, artifacts.

Inventory is grouped into three sub-areas:

- **`access_model/`** — the business access vocabulary: capabilities, capability mappings, capability grants.
- **`policy/`** — policy definitions: SoD rules, conditions.
- **`assessment/`** — assessment results: findings, mitigations, feedback, scan runs.

Inventory is not just CRUD. It accepts changes, emits domain events, and upholds invariants through its service layer. But it does not orchestrate multi-step processes — that is the job of the layer above.

## Engines

Engines actively *do* something with data: ingest, reconcile, project, assess, orchestrate. Engines own no ORM models and add no migrations — they use Inventory and Platform services.

Current engines:

- **`ingest`** — connector result ingestion (ingress).
- **`reconciliation`** — set-diff between observed and current state per application (ingress).
- **`sync_apply`** — applies the reconciliation delta into the lake's `normalized.access_facts` table (ingress / internal).
- **`effective_access`** — builds and maintains the current factual access picture (Effective Access Store).
- **`policy_assessment`** — evaluates policy against facts and context, returning a `PolicyAssessmentOutput` / `Decision`. Has two strategies: `deterministic` (YAML rule-pack) and `semantic_assisted` (semantic evidence extraction over `platform/llm`).
- **`access_analysis`** — batch / retrospective analysis of existing access state (capability projection, SoD scans, findings).
- **`access_orchestration`** — live orchestration of intents to change or validate access: employee requests, JML events, manager and admin actions, remediation, SoD mitigation, API/import-driven operations. Delegates to `policy_assessment`, `effective_access`, `provisioning`, and (later) workflow.
- **`provisioning`** — applies access changes to external systems (egress).
- **`lake_migration`** — one-shot lake schema migrations.

## Where to put new code

| What you are adding | Where |
|---|---|
| New persistent entity with a CRUD API | Inventory |
| Infrastructure service (connector, logs, LLM provider) | Platform |
| Multi-step process or engine | Engines |
| Shared mechanics with no domain meaning (sessions, queues) | `core/` |
