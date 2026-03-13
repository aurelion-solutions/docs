# Access Model

Aurelion represents access as a pipeline from raw connector data to a normalized current-state snapshot. Each stage of the pipeline has one responsibility and never replaces another.

## The pipeline

```
Connector
    │
    ▼
AccessArtifact  ← append-only, raw data
    │
    ▼ (normalization / reconciliation)
    │
    ├──→ Resource         ← what is being accessed
    ├──→ AccessFact       ← who can do what right now
    └──→ ArtifactBinding  ← audit link: artifact ↔ fact
```

## AccessArtifact — raw data

When a connector reports that "Ivan has the Admin role in GitHub", this is recorded as an **AccessArtifact**. Artifacts are *append-only*: they are never deleted or modified. They are a chronicle of what connectors have seen.

An artifact carries an `artifact_type` (e.g. `role`, `acl_entry`, `db_grant`) that determines which handler will process it. The payload is arbitrary JSON in the source system's own vocabulary.

## Resource — the normalized target

A **Resource** is the normalized representation of the object being accessed: a repository, a database, a role, a file share. A Resource is unique within an Application by `(resource_type, resource_key)`.

Resources are resolve-or-create: if a resource with that key already exists, the existing record is reused. This makes normalization idempotent.

## AccessFact — current access state

An **AccessFact** is a statement about what exists right now: "Subject X has Action Y on Resource Z." This is *current state*, not history.

Facts are mutable in one direction only: they can be revoked, updated for field drift, but never duplicated on the natural key `(subject_id, account_id, resource_id, action_id)`. If the same fact arrives again, it is reactivated rather than created anew.

## Action — the controlled vocabulary

**Action** is what is permitted. Aurelion uses seven canonical verbs: `read`, `write`, `execute`, `approve`, `admin`, `use`, `own`. This is reference data — connectors and handlers must map their own vocabulary into these terms. An unknown verb is rejected.

## Account — the identity in the remote system

**Account** is a user account in a specific Application: username, email, status. Accounts are normalized from connector data during reconciliation.

An AccessFact can be linked to an Account or directly to a Subject, depending on how the source system models access.

## ArtifactBinding — the audit trail

**ArtifactBinding** links an artifact to what was produced from it: an AccessFact, a Resource, an Account, or a Subject. A binding is created each time an artifact is processed or during reconciliation.

A binding is an audit thread: it always answers the question "where did this access fact come from?"

## Summary

| Entity | What it is | Mutability |
|---|---|---|
| AccessArtifact | Raw data from a connector | Append-only |
| Resource | Normalized access target | Resolve-or-create |
| AccessFact | Current state of "who can do what" | Revoke / drift-update |
| Account | Account in a specific system | Updated by reconciliation |
| ArtifactBinding | Audit link: artifact ↔ result | Immutable |
