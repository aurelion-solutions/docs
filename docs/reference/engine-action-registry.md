# Engine Action Registry

Reference for the `@register_action` decorator, `ActionContext`, and the
registered-action catalogue.

Source of truth: `aurelion-kernel/src/platform/orchestrator/registry.py`.

## The decorator

```python
@register_action(
    engine="inventory_reconcile",
    action="run",
    args_schema=ReconcileArgs,
    result_schema=ReconcileResult,
    idempotent=True,
)
async def run(args: ReconcileArgs, ctx: ActionContext) -> ReconcileResult:
    ...
```

Signature:

```python
register_action(
    engine: str,
    action: str,
    args_schema: type[BaseModel],
    result_schema: type[BaseModel],
    idempotent: bool = True,
) -> Callable[[ActionHandler], ActionHandler]
```

| Parameter | Description |
|---|---|
| `engine` | Non-empty identifier for the owning engine (e.g. `"access_apply"`) |
| `action` | Non-empty identifier for the specific action (e.g. `"create_account"`) |
| `args_schema` | Pydantic `BaseModel` subclass describing the handler's input |
| `result_schema` | Pydantic `BaseModel` subclass describing the handler's output |
| `idempotent` | Metadata flag. `True` (default) is the only value used in Phase 18 |

The decorator returns the original function unchanged so it remains independently
callable. Registration happens at import time and is single-threaded.

`idempotent=True` is the only permitted Phase-18 value (ARCH_CONTEXT line 356).
The registry stores the flag faithfully; enforcement is a future runner concern.

## ActionContext

`ActionContext` is a frozen dataclass injected into every action handler by the
runner. The runner owns the transaction — the action **must not** call
`session.commit()` or open its own session. Exceptions propagate to the runner,
which rolls back.

| Field | Type | Description |
|---|---|---|
| `session` | `AsyncSession` | The runner's active SQLAlchemy async session |
| `log_service` | `LogService` | Injected logger; use `emit_safe` for observability |
| `pipeline_run_id` | `uuid.UUID` | ID of the owning `PipelineRun` |
| `step_run_id` | `uuid.UUID` | ID of the current `StepRun` attempt |
| `attempt` | `int` | Attempt counter for the current step (1-based) |
| `worker_id` | `str \| None` | `<hostname>-<pid>-<slot_index>` of the executing worker |

## Pydantic contract

`args_schema` and `result_schema` must be Pydantic v2 `BaseModel` subclasses.
JSON Schema is derived from them via `model_json_schema()` and is surfaced at
`GET /api/v0/.well-known/pipeline-schema.json` (injected into `$defs.action_args`
and `$defs.action_results`).

Dispatch is the **sole** validation point for action args. Handler implementations
must not re-validate args manually — the registry validates them before the
handler is called.

## Engine-key naming

Action keys use dotted notation: `<engine>.<action>` (e.g.
`policy_assessment.sod.evaluate`). The registry stores `engine` and `action`
separately; the dotted form is assembled by callers (discovery, pipeline YAML).
Key components are opaque to the registry and are not URL-safe without
percent-encoding.

## Exceptions

All exceptions inherit from `ActionRegistryError`.

| Exception | When raised |
|---|---|
| `DuplicateActionError` | The same `(engine, action)` pair is registered twice |
| `ActionNotFoundError` | `(engine, action)` is not found in the registry |
| `ActionArgsValidationError` | Raw args fail `args_schema` validation |
| `ActionResultValidationError` | Handler return value fails `result_schema` validation |

## Currently registered actions

The table below lists every `(engine, action)` pair registered in `ACTION_REGISTRY`
as of Phase 19 Step A4. The live catalogue (with arg/result schemas) is available
at `GET /api/v0/.well-known/pipeline-actions.json`.

Actions marked `idempotent=yes` are safe for the runner to retry. For
connector-backed actions (`access_apply.*`) this is a **delegated contract** —
Aurelion does not retry across `connector.invoke`; the target connector must
guarantee that repeated invocations with the same args produce the same end state.

| Key (engine.action) | idempotent | Description |
|---|---|---|
| `access_effective.list_grants` | yes | Return a page of effective grants matching given filters |
| `access_effective.explain_access` | yes | Deny-wins aggregation for a (subject, resource, action) triple |
| `access_effective.get_grant` | yes | Fetch a single effective grant by id |
| `access_effective.project_access_fact` | no | Project all (fact, initiative) pairs for one AccessFact into effective_grants |
| `access_effective.project_application` | yes | Project all (fact, initiative) pairs for one Application into effective_grants |
| `access_effective.apply_incremental_change` | no | Apply one incremental inventory event to the effective_grants projection |
| `inventory_reconcile.run` | yes | Run a full reconciliation cycle for one application |
| `inventory_reconcile.master_data_apply` | yes | Apply reconciliation delta items for one entity type (persons, accounts, etc.) |
| `inventory_sync.apply` | yes | Apply approved reconciliation delta items to normalized.access_facts |
| `policy_assessment.sod.evaluate` | yes | Evaluate SoD policy for a given subject and access set |
| `policy_assessment.sod.what_if` | yes | What-if SoD evaluation for a proposed access change |
| `access_analysis.assessment_preview.detect_orphans` | yes | Detect orphaned access across an application |
| `access_analysis.assessment_preview.detect_terminated` | yes | Detect terminated-subject access across an application |
| `access_analysis.capability_preview.resolve` | yes | Resolve capability-to-grant mapping for a subject |
| `access_analysis.reports.deterministic` | yes | Run a deterministic access analysis report |
| `access_apply.create_account` | yes | Provision a new account on a target application via connector |
| `access_apply.delete_account` | yes | Remove an account from a target application via connector |

## Source of truth

- `aurelion-kernel/src/platform/orchestrator/registry.py`
