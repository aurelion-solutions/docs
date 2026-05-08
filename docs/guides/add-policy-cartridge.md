# Add a policy cartridge

Step-by-step guide for adding a new file-based policy cartridge to a
kernel checkout. Audience: a kernel contributor or platform engineer with
a local development environment.

For the conceptual model, see [Policy Cartridges (concepts)](../concepts/policy-cartridges.md).
For the YAML schema and DSL operators, see [Policy Cartridges (reference)](../reference/policy-cartridges.md).
For deploying an existing cartridge into a running system, see the
[Policy Cartridge Operations](../operations/policy-cartridge-operations.md) runbook.

## Prerequisites

- A local kernel checkout with `uv sync` complete.
- The kernel test suite runs cleanly: `uv run pytest`.
- You know which `policy_type` the cartridge belongs to (`access_risk` or
  `lifecycle` today). Adding a new policy type is a separate code change.

## 1. Create the YAML file

Pick a slug `<name>` for the cartridge. Drop the file at:

```
cartridges/lens/<policy_type>/<name>.yaml
```

The directory immediately under `lens/` MUST equal the cartridge's
`policy_type` field.

Use the [reference schema](../reference/policy-cartridges.md#yaml-schema).
At minimum:

```yaml
id: lens.<policy_type>.<name>
version: 1
name: Human-readable name
description: One-line description.
policy_type: <policy_type>
rule_id: lens.<policy_type>.<name>
assessment_strategy: deterministic
requires:
  <fact.path>: string
condition:
  equals:
    fact: <fact_name>
    value: true
decision:
  action: flag_for_review
  risk_level: medium
finding:
  title: <Finding title>
  severity: medium
  remediation: One sentence on what to do.
```

The `condition` block must use only [supported DSL operators](../reference/policy-cartridges.md#dsl-operators):
`all`, `any`, `equals`, `not_equals`, `is_null`, `is_not_null`, `greater_than`.

## 2. Wire the policy cartridge into the engine (only if invoked by ScanEngine)

If the cartridge needs to fire during a scan run, add a per-candidate call
in `aurelion-kernel/src/engines/access_analysis/engine.py`:

1. Add a path constant near the existing `_*_CARTRIDGE` constants:

   ```python
   _MY_CARTRIDGE: Path = (
       Path(__file__).resolve().parents[4]
       / 'cartridges' / 'lens' / '<policy_type>' / '<name>.yaml'
   )
   ```

2. In `ScanEngine.run`, build a context dict from data the engine already
   loads, call the cartridge service, and convert the output into a
   `Finding` upsert. Mirror the orphan / terminated / unused branches.

The engine builds the context dict from data it already loads — adding a
policy cartridge does not introduce new I/O. If the cartridge needs facts
the engine does not currently load, add the loader call separately and
review the architectural impact.

## 3. Add a structural test

Add an end-to-end test under
`aurelion-kernel/src/engines/policy_assessment/tests/test_lens_cartridges_e2e.py`
that invokes the cartridge through `PolicyCartridgeAssessmentService` for
both a matching and a non-matching context.

If the cartridge is invoked by ScanEngine, also add an integration test
under `aurelion-kernel/src/engines/access_analysis/tests/` mirroring the
existing `test_engine_cartridge_*.py` pattern.

## 4. Run the relevant test suites

```bash
cd aurelion-kernel
uv run pytest \
  src/inventory/policy/cartridges/ \
  src/engines/policy_assessment/tests/ \
  src/engines/access_analysis/tests/
```

This catches:

- Schema and DSL parse errors.
- Misplaced YAML (cartridge under wrong `policy_type` directory).
- Missing or wrong context fields in the engine call.

## 5. Lint

```bash
ruff check . --fix
ruff format .
```

The checklist for a complete change in this codebase is `code +
tests + ruff clean + CHANGELOG`. The CHANGELOG entry goes into
`aurelion-kernel/CHANGELOG.md` under the Added/Changed section.

## What's next

- For the deploy/rollback procedure once the cartridge is merged, see the
  [Policy Cartridge Operations](../operations/policy-cartridge-operations.md) runbook.
- For changing severity or the condition of an existing policy cartridge,
  the same procedure applies — only the YAML edit + tests are usually
  needed.
