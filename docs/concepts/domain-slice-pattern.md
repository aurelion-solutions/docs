# Domain Slice Pattern

Every backend capability in `aurelion-kernel` follows the same
file-level shape: a small set of co-located modules with strict
responsibilities. This is the unit of organization the kernel uses to
keep business logic, validation, persistence, and HTTP handling
separately addressable.

## The shape

A slice is a directory under the appropriate layer:

```
src/<layer>/<slice>/
├── models.py      # SQLAlchemy ORM rows
├── schemas.py     # Pydantic v2 validation models
├── service.py     # Business logic; the only place that emits events
├── routes.py      # Thin HTTP handlers
└── tests/         # Service tests + API tests
```

Layers:

| Layer | What lives there |
|---|---|
| `inventory/` | Domain entities (Employee, Account, Resource, …). |
| `engines/` | Capability engines (reconciliation, access_apply, access_analysis, notifications, …). |
| `platform/` | Platform services (events, logs, secrets, storage, orchestrator, …). |
| `core/` | Infrastructure (config, MQ, DB session). |

Dependencies flow downward: `inventory` may depend on `platform` and
`core`; `engines` may depend on `inventory`, `platform`, and `core`;
neither depends on a product. Products live outside the kernel.

## Module contracts

### `models.py`

SQLAlchemy ORM rows. Columns, constraints, and indices.

- Models do **not** emit events.
- Models do **not** call services or routes.
- A model never depends on Pydantic.

### `schemas.py`

Pydantic v2 models for request validation, response shaping, and
internal DTOs. Three idiomatic shapes per entity:

- `<Entity>Create` — request body for `POST`.
- `<Entity>Read` — response shape; usually `from_attributes=True` so
  `model_validate(orm_row)` works directly.
- `<Entity>Patch` — partial-update body for `PATCH`; `extra="forbid"`
  to reject unknown fields.

Schemas describe shape only. They do not access the database.

### `service.py`

Business logic. The service holds an `AsyncSession` and orchestrates
reads, writes, validation, and event emission.

Three invariants:

- **Service is the only emitter.** Events are emitted from
  `service.py`. Never from `models.py` or `routes.py`.
- **Service does not own the transaction.** It calls `session.flush()`
  when needed; it never calls `session.commit()` or `session.rollback()`.
  The caller (an HTTP handler, an event consumer, a pipeline runner)
  owns the boundary.
- **Service is testable without HTTP.** Service-layer tests construct
  a session, call the method, and assert the persisted state and the
  emitted events. They never go through the FastAPI app.

### `routes.py`

Thin HTTP handlers — validate input, call the service, return the
response. No business logic. A handler typically fits in five lines:

```python
@router.post("", status_code=201, response_model=EntityRead)
async def create_entity(
    body: EntityCreate,
    service: EntityService = Depends(get_entity_service),
) -> EntityRead:
    row = await service.create(body)
    return EntityRead.model_validate(row)
```

Routes are registered in `src/routers/v0.py`. Names follow two rules:

- **Singular class name** — `Employee`, `Account`, `Resource`.
- **Plural route path** — `/employees`, `/accounts`, `/resources`.

## Why this shape

The slice pattern is the kernel's answer to four recurring problems:

1. **Event ownership is unambiguous.** Searching for who emits
   `inventory.employee.created` always lands in
   `inventory/employees/service.py`. There is no second site.
2. **Routes stay reviewable.** A pull request that touches HTTP
   surface usually does not touch business logic, and vice versa.
3. **Tests align with concerns.** Service tests cover business rules;
   API tests cover HTTP contracts. Neither has to do both.
4. **Layers can be enforced statically.** Import direction
   (`product → engine → platform`) is a single rule that the import
   linter checks across the codebase.

## What a slice does *not* do

- A slice does not own its own MQ topology — the platform layer
  (`platform/events/`, `platform/orchestrator/`) does.
- A slice does not embed a connector — connectors live alongside their
  engine (`engines/reconciliation/connectors/`).
- A slice does not run a runtime — runtimes are composition roots
  under `src/runtimes/`.

## See also

- [Platform Layers](layers.md) — the layering rules that constrain
  what a slice can depend on.
- [Add an engine action](../guides/add-engine-action.md) — practical
  guide for adding capability to the engines layer.
