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

```
Employee  ──┐
NHI       ──┼──→ Subject  ──→ access decisions, audit log
Customer  ──┘
```

## Summary

If you are thinking about *who this is*, look at Employee / NHI / Customer.  
If you are thinking about *what this principal is allowed to do*, work with Subject.  
If you are thinking about *where the data about a person came from*, look at EmployeeRecord.
