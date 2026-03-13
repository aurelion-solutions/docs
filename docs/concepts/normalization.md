# Normalization

Normalization is the path raw connector data takes to become a normalized access graph. It is an ingest-time operation: it runs each time data arrives from a connector.

## Why it exists

Each source describes access in its own language. In an ACL: `verb=admin`. In SAP: `tcode=FB01`. In a database: `GRANT SELECT ON table`. Aurelion has one action vocabulary (`read`, `write`, `execute`, `admin`, `use`, `own`). Normalization translates.

## The pipeline

```
Raw payload
    │
    ▼
[1] AccessArtifact → written as-is (append-only)
    │
    ▼
[2] Normalizer function (pure) → translates to NormalizedAccess
    │
    ▼
[3] Resource → resolve-or-create by external_id
    │
    ▼
[4] AccessFact → created by natural key (with SAVEPOINT)
    │
    ▼
[5] ArtifactBinding → links artifact to fact and resource
```

Step 2 is a pure function with no I/O. Everything else touches the database.

## Idempotency

The pipeline can be run any number of times with the same data — the result does not change:

- `AccessArtifact` — append-only; each call creates a new row
- `Resource` — resolve-or-create; an existing resource is reused without modification
- `AccessFact` — on a duplicate natural key, the existing row is returned silently
- `ArtifactBinding` — always new (bound to the specific artifact)

## Normalizer contract

Each source (ACL, SAP, LDAP, ...) provides:

1. **A pure normalizer function** — translates the source payload into `NormalizedAccess`. An unknown verb or type raises a typed error; there are no silent fallbacks.

2. **An orchestrator service** — calls Inventory services in the right order. It emits no events of its own — events are emitted by the Inventory services it calls.

## Normalization vs reconciliation

| | Normalization | Reconciliation |
|---|---|---|
| When | On each connector data arrival | On demand / schedule |
| What it does | Translates a single payload into an access fact | Synchronizes the full state of an Application |
| Scope | One artifact | The entire Application |
| Can revoke | No | Yes |

Normalization is a building block. Reconciliation is a full sync.

## Events emitted

The normalization pipeline emits no `normalization.*` events of its own. The orchestrator is pure composition — each Inventory service it calls emits its own event when state changes. This avoids redundant events with no new information.

| Event | When |
|---|---|
| `inventory.access_fact.created` | New fact written |
| `resource.created` | New resource resolved |
| `access_artifact.created` | Artifact recorded |
| `artifact_binding.created` | Binding created |
