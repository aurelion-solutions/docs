# How to onboard an employee

This guide covers creating an employee identity in Aurelion manually via the API. In production, employees are typically ingested from HR systems via connectors and the employee record composition resolver. This guide is useful for testing and for environments without a live HR connector.

## The identity hierarchy

An employee requires two records:

1. **Person** — the reusable human profile root
2. **Employee** — the canonical internal identity, linked to the Person

These are two separate API calls. You cannot create an Employee without a Person.

## Step 1: Create a Person

```bash
curl -X POST http://localhost:8000/api/v0/persons \
  -H "Content-Type: application/json" \
  -d '{
    "external_id": "emp-001",
    "description": "Jane Doe"
  }'
```

Save the returned `id` — you will need it in the next step.

```json
{
  "id": "aaaa0000-0000-0000-0000-000000000001",
  "external_id": "emp-001",
  "description": "Jane Doe"
}
```

## Step 2: Create an Employee

```bash
curl -X POST http://localhost:8000/api/v0/employees \
  -H "Content-Type: application/json" \
  -d '{
    "person_id": "aaaa0000-0000-0000-0000-000000000001",
    "description": "Jane Doe"
  }'
```

```json
{
  "id": "bbbb0000-0000-0000-0000-000000000002",
  "person_id": "aaaa0000-0000-0000-0000-000000000001",
  "is_locked": false,
  "description": "Jane Doe"
}
```

## Step 3: Add attributes (optional)

Attributes are key-value pairs used by the Policy Decision Point for rule evaluation. Common attributes: `department`, `employment_status`, `risk_score`, `mfa_enrolled`.

```bash
curl -X POST http://localhost:8000/api/v0/employees/bbbb0000-0000-0000-0000-000000000002/attributes \
  -H "Content-Type: application/json" \
  -d '{"key": "department", "value": "engineering"}'

curl -X POST http://localhost:8000/api/v0/employees/bbbb0000-0000-0000-0000-000000000002/attributes \
  -H "Content-Type: application/json" \
  -d '{"key": "employment_status", "value": "active"}'
```

Attributes are unique per employee by key. Adding a duplicate key returns `409`.

## Step 4: Verify

```bash
al employees get bbbb0000-0000-0000-0000-000000000002
al employees attributes bbbb0000-0000-0000-0000-000000000002
```

## Locking an employee

To lock an employee (block access without deleting the record):

```bash
curl -X PATCH http://localhost:8000/api/v0/employees/bbbb0000-0000-0000-0000-000000000002 \
  -H "Content-Type: application/json" \
  -d '{"is_locked": true}'
```

The PDP checks `is_locked` as part of lifecycle rules. A locked employee will typically receive a `deny` decision regardless of their access facts.

## From source systems: EmployeeRecord

If you are ingesting employees from an HR system or directory service, the flow is different: the connector creates **EmployeeRecord** entries, and the composition resolver maps them to canonical Employee records based on attribute matching rules. The manual steps above bypass this — use them only when you need direct control.
