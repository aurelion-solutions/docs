# How to add a new engine action

Use this guide when you have implemented a new capability in an engine slice
and want pipelines to be able to call it as an orchestrated step.

## What you need

- A target engine slice (e.g. `engines/foo`) with the business logic already
  implemented in that engine's `service.py`.
- An `actions.py` module inside the engine slice, or willingness to create one.
- Familiarity with the engine-action contract described in
  [`../reference/engine-action-registry.md`](../reference/engine-action-registry.md).

## Step 1 — Define args and result schemas

Create Pydantic v2 models for the action's inputs and outputs.  Keep them in
`actions.py` (or in a dedicated `schemas.py` if the slice already has one):

```python
from pydantic import BaseModel, ConfigDict


class FooBarArgs(BaseModel):
    model_config = ConfigDict(frozen=True)

    target_id: str
    dry_run: bool = False


class FooBarResult(BaseModel):
    model_config = ConfigDict(frozen=True)

    processed: int
    skipped: int
```

`frozen=True` prevents accidental mutation inside the action body.  Both models
must be Pydantic v2 `BaseModel` subclasses — no hand-written JSON Schema.
Full rules are in
[`../reference/engine-action-registry.md#pydantic-contract`](../reference/engine-action-registry.md#pydantic-contract).

## Step 2 — Write the async action function

The function signature is fixed by the registry contract:

```python
from src.platform.orchestrator.registry import ActionContext


async def bar(ctx: ActionContext, args: FooBarArgs) -> FooBarResult:
    result = await ctx.session.execute(...)  # call your service / repo
    return FooBarResult(processed=result.count, skipped=0)
```

Rules:

- The function **must** be `async`.
- The signature **must** be exactly `(ctx: ActionContext, args: YourArgsModel)`.
- The return type **must** be a Pydantic model.
- Use `ctx.session` for any DB I/O — do **not** open a new session.
- Do **not** call `ctx.session.commit()`.  The runner owns the transaction.

## Step 3 — Register with the decorator

Apply `@register_action` directly above the function:

```python
from src.platform.orchestrator.registry import register_action

@register_action(engine="foo", action="bar", idempotent=True)
async def bar(ctx: ActionContext, args: FooBarArgs) -> FooBarResult:
    ...
```

The `engine` key follows the dotted naming rule:

- Top-level slices use a plain slug: `engine="foo"`.
- Sub-slices use dotted notation: `engine="policy_assessment.sod"`.
- No spaces, no hyphens, no URL path separators.

Full naming rules are in
[`../reference/engine-action-registry.md#engine-key-naming`](../reference/engine-action-registry.md#engine-key-naming).

## Step 4 — Decide on `idempotent=`

`idempotent=True` is mandatory in the current phase.  Before you set it,
verify the action actually satisfies the contract:

| Situation | What to do |
|---|---|
| Running the action twice with identical args produces the same observable end state (e.g. status-guarded UPDATE, insert-or-ignore, lake scan dedup). | Set `idempotent=True` — you are done. |
| The action has a side effect that is not naturally deduplicated. | Make it deduplicated first (add a status guard, a UNIQUE constraint, or a pre-check), then set `idempotent=True`. |
| You cannot make it idempotent without significant refactoring. | Do not merge it yet — the contract is a hard requirement. |

See
[`../concepts/idempotency-and-reclaim.md#the-contract`](../concepts/idempotency-and-reclaim.md#the-contract)
for the formal definition and real-world examples.

## Step 5 — Wire registration via side-effect import

The `@register_action` decorator runs at import time and adds the action to the
global `ACTION_REGISTRY`.  This means `actions.py` must be imported at least
once during executor startup, or the action will be invisible to the runner.

Ensure that the executor bootstrap (or your engine's `__init__.py`) includes
an import of `actions.py`:

```python
# engines/foo/__init__.py  (or the executor entrypoint)
from engines.foo import actions as _  # noqa: F401  side-effect import
```

Full details on bootstrap order are in
[`../reference/engine-action-registry.md#the-decorator`](../reference/engine-action-registry.md#the-decorator).

## Step 6 — Add unit and integration tests

Two tests are the minimum:

1. **Registry presence** — import `actions.py`, then assert that
   `ACTION_REGISTRY.get(("foo", "bar"))` is not `None`.  This catches a
   missing import at startup.
2. **Happy-path dispatch** — call `ACTION_REGISTRY.dispatch("foo", "bar", args,
   ctx)` in a test that supplies a real DB session (or a mock).  Assert the
   returned `FooBarResult` matches expected values.

## Step 7 — Use it in a YAML pipeline

Add a step to a pipeline definition in `aurelion-kernel/pipelines/`:

```yaml
name: foo_workflow
version: "1.0.0"

triggers:
  - type: mq
    routing_key: foo.trigger.run

steps:
  - name: run_bar
    type: engine_call
    engine: foo
    action: bar
    args:
      target_id: "{{ trigger.payload.target_id }}"
      dry_run: false
    next: done

  - name: done
    type: terminal
```

The `engine_call` step type and its `args` templating are described in
[`../reference/pipeline-yaml.md#engine_call`](../reference/pipeline-yaml.md#engine_call).

## See also

- [`../reference/engine-action-registry.md`](../reference/engine-action-registry.md) — full decorator and contract reference
- [`../concepts/idempotency-and-reclaim.md`](../concepts/idempotency-and-reclaim.md) — why idempotency is required and how to achieve it
- [`../reference/pipeline-yaml.md`](../reference/pipeline-yaml.md) — YAML grammar for pipelines that call engine actions
