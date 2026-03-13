# Platform Layers

Aurelion is built as a three-layer pyramid. Layers define what each part owns and who can call whom. Dependencies flow downward only — upper layers know about lower ones, never the reverse.

```
┌─────────────────────────────────────────┐
│  Capabilities (Layer 2)                 │  engines and orchestrators
│  reconciliation · normalization · PDP   │
├─────────────────────────────────────────┤
│  Inventory (Layer 1)                    │  domain data and its API
│  persons · accounts · access facts ...  │
├─────────────────────────────────────────┤
│  Platform (Layer 0)                     │  infrastructure
│  connectors · logs · secrets · DB       │
└─────────────────────────────────────────┘
```

## Platform

The infrastructure layer. It knows nothing about your employees or access rights — it knows about connections, logs, and the database.

This is where the connector instance registry, RabbitMQ clients, secret provider, data lake storage factory, and logging live. If a component is needed by all other layers and has no domain meaning, it belongs in Platform.

## Inventory

The primary source of truth for domain data. Everything Aurelion stores long-term lives here: people, NHIs, accounts, resources, access facts, artifacts.

Inventory is not just CRUD. It accepts changes, emits domain events, and upholds invariants through its service layer. But it does not orchestrate multi-step processes — that is the job of the layer above.

## Capabilities

Engines that actively *do* something with data: normalize, reconcile, make decisions. Capabilities own no ORM models and add no migrations — they use Inventory and Platform services.

Three core engines:

- **Normalization** — converts raw connector data into a normalized access graph
- **Reconciliation** — synchronizes current access state with what artifacts describe
- **Policy Decision Point** — answers "is this access permitted?"

## Where to put new code

| What you are adding | Where |
|---|---|
| New persistent entity with a CRUD API | Inventory |
| Infrastructure service (connector, logs) | Platform |
| Multi-step process or engine | Capabilities |
| Shared mechanics with no domain meaning (sessions, queues) | `core/` |
