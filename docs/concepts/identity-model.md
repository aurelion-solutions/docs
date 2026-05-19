# Identity Model

Aurelion distinguishes three kinds of principals: people inside the organization, people outside it, and non-human identities. All of them converge in a single abstraction — **Subject** — which is what the platform uses when making access decisions.

## Human identities

### Internal: Person → Employee

Aurelion separates a *person's profile* from their *role in the organization*.

**Person** is the reusable root. It stores the minimum: an external identifier and extensible attributes. A Person exists independently of whether the individual is currently an employee.

**Employee** is the canonical internal identity. Policies, resource ownership, and reconciliation rules all work with Employee. An Employee can carry a lock flag.

### EmployeeRecord — the source-side record

HR systems, Active Directory, and other external sources each describe people in their own way. Each such record is an **EmployeeRecord**, owned by a specific Application (the connector to that source).

One Employee can be composed from multiple EmployeeRecords via a **resolver**. The resolver matches records from different sources to a single canonical Employee using attribute mapping rules. This allows AD and the HR system to talk about the same person in different terms — Aurelion knows they are the same Employee.

```
EmployeeRecord (AD)  ──┐
EmployeeRecord (HR)  ──┼──→ Employee (canonical) ──→ Person
EmployeeRecord (JIRA)──┘
```

## Non-human identities (NHI)

**NHI** covers service accounts, bots, CI pipelines, and daemons. They are fundamentally different from people: no employee lifecycle, no HR records, no MFA.

An NHI has a kind, can be linked to an owner Employee, and can be associated with the Application that created it. NHIs participate in policies and audit on equal footing with humans.

## External users: Customer

**Customer** is a person who uses your product as a client — not an employee of the organization. A Customer has tenancy, a plan tier, MFA and lock flags. Their status lives on Subject.

## Subject — the convergence point

**Subject** is the abstraction that unifies all principal types for policies and audit. When the Policy Decision Point makes a decision or when Aurelion records an access event, it operates on a Subject, not on a specific type.

A Subject points to exactly one of three things: an Employee, an NHI, or a Customer. The Subject's status (active, suspended, locked, deleted) is denormalized automatically when the underlying entity changes state.

Every principal has exactly one Subject, and the kernel maintains that invariant automatically: whenever an Employee, NHI, or Customer is created — over HTTP, via bulk upsert, or by the reconcile-apply step — the matching Subject row is inserted in the same transaction. Consumers can rely on `subject_ref` resolving for any principal that exists.

```
Employee  ──┐
NHI       ──┼──→ Subject  ──→ access decisions, audit log
Customer  ──┘
```

## Internal vs external org units

Org units carry a single platform-level flag, `is_internal`, that splits the org tree into "ours" (`true`, the managed identity space) and "not ours" (`false`, external parties such as partner companies the platform tracks but does not govern). Default is `true`.

The flag is deliberately thin. It answers exactly one question: does this node belong to the identity space we manage? HR-style concepts — contractor company metadata, engagement start and end dates, contract owner, contract type — are **not** here. They live in the product layer, which is where the operational lifecycle of an external engagement actually plays out. Keeping kernel free of that vocabulary is what lets reconciliation, policy evaluation, and the data lake treat an org unit as a pure tree node.

A per-tree invariant holds: every node in a connected tree shares the same `is_internal` value. The kernel enforces this with a `BEFORE INSERT OR UPDATE` trigger that rejects any row whose value disagrees with its parent or any child. A consequence is that flipping `is_internal` on a multi-node subtree is not supported via plain UPDATE — admins drop and recreate. Single-node flips work normally.

External org units (`is_internal=false`) are operator-managed: the UI calls per-row CRUD endpoints on the kernel (`POST/GET/PATCH/DELETE /api/v0/org-units[/{id}]`) and that is the only way they enter the system. Internal org units stay reconcile-managed via the bulk ingest path. External rows are never reconciled from connectors and never written to the data lake — the `raw.org_units` Iceberg schema has no `is_internal` column, and the bulk endpoint silently drops the field. This asymmetry is by design: the lake is for sources of truth that connectors maintain, and external parties are by definition not one of those.

The link from a person-in-role to that partition is `employees.org_unit_id` → `org_units.id`. The kernel exposes the column on `EmployeeCreate` / `EmployeeRead` and on the paginated list envelope, so any REST client reads the same shape. The kernel itself does not constrain which side of the partition an employee can bind to: it accepts any existing `org_unit_id`. The "contractor employees bind to contractor org-units only" rule is a product-layer policy enforced by the consuming UI; admin tooling and internal fixtures use the same endpoint without paying that cost.

Anything wanting an "internal vs external population" split reads `is_internal` and decides; it does not invent a parallel taxonomy.

See the [Org Unit reference](../reference/org-units.md) for fields, trigger semantics, and the paginated list contract.

## Summary

If you are thinking about *who this is*, look at Employee / NHI / Customer.  
If you are thinking about *what this principal is allowed to do*, work with Subject.  
If you are thinking about *where the data about a person came from*, look at EmployeeRecord.  
If you are thinking about *whether an org unit is part of the managed identity space*, look at `org_units.is_internal`.
