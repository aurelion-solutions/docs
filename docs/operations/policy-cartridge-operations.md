# Policy Cartridge Operations

Procedure for shipping a new or modified file-based policy cartridge into
a running deployment. Covers four steps: **pre-flight**, **deploy**,
**verify**, and **rollback**.

For the conceptual model, see
[Policy Cartridges (concepts)](../concepts/policy-cartridges.md). For the
YAML schema and DSL, see [Policy Cartridges (reference)](../reference/policy-cartridges.md).

This runbook does not apply to SoD rules — those are DB-backed and managed
through the `SodRule` REST/CLI surface, not through YAML files.

## When to use

- Adding a new policy cartridge under `cartridges/lens/<policy_type>/`.
- Editing the condition, severity, or finding metadata of an existing cartridge.
- Removing or disabling a cartridge.

## Prerequisites

- Write access to the deployment's `cartridges/lens/` directory.
- A way to roll back the file change (git revert, file backup, or
  configuration-management tooling).
- Access to the kernel test suite (`uv run pytest`) for pre-flight validation.
- Ability to invoke a scoped scan run (`POST /api/v0/scan-runs/{id}/run`)
  for verification.

## Step 1 — Pre-flight (validate locally)

Run before touching the deployment.

```bash
cd aurelion-kernel
uv run pytest \
  src/inventory/policy/cartridges/ \
  src/engines/policy_assessment/tests/ \
  src/engines/access_analysis/tests/test_engine_cartridge_*.py
```

What this catches:

- Malformed YAML (`CartridgeLoadError`).
- Schema violations against `CartridgeManifest` (wrong field types, missing required keys, invalid `policy_type`).
- DSL operators that don't exist or are misspelled.
- Structural mistakes in the runnable directory (cartridge placed under wrong `policy_type` parent).

If any of those tests fail, stop. Fix the YAML and re-run.

If you are editing severity (`decision.risk_level`), additionally make sure
the cartridge end-to-end test under `test_lens_cartridges_e2e.py` reflects
the new value, otherwise CI will catch it later.

## Step 2 — Deploy

Policy cartridge files are loaded **on demand** by
`FileCartridgeLoader.load_file(path)` when a scan run invokes
`PolicyCartridgeAssessmentService.evaluate_file(...)`. There is no
in-process cache and no startup-time registry.

Practical consequence: a file edit takes effect on the **next** scan run
that loads that path. No `platform_api` restart is required.

| Change type | Action |
|---|---|
| Add new policy cartridge | Drop the YAML at `cartridges/lens/<policy_type>/<name>.yaml`. The directory immediately under `lens/` MUST equal the cartridge's `policy_type`. |
| Edit existing policy cartridge | Replace the file in place. |
| Disable a policy cartridge | Move the file out of `cartridges/lens/` (e.g. into `cartridges/templates/`) or delete it. |

Do not stage runnable policy cartridges under `cartridges/templates/` —
that directory is documentation only and is intentionally invisible to
the loader.

## Step 3 — Verify (after deploy)

Trigger a scoped scan and confirm the cartridge fires (or stops firing) as
expected.

```bash
# 1. Create a pending scan with a narrow scope you can predict.
curl -X POST -H 'Content-Type: application/json' \
     -d '{"trigger": "manual", "scope_application_id": "<uuid>"}' \
     http://kernel/api/v0/scan-runs

# 2. Run it.
curl -X POST http://kernel/api/v0/scan-runs/<id>/run

# 3. Check the findings produced.
curl 'http://kernel/api/v0/findings?scan_run_id=<id>'
```

What to check:

- The expected `kind` of finding appears (or does not appear).
- The `severity` field on the finding matches the cartridge's `decision.risk_level`.
- Existing findings of that kind keep their stored severity until they are
  re-emitted by a fresh scan — the rollup is per-run, the row is per-event.

If the result does not match expectations, see [Common failures](#common-failures).

## Step 4 — Rollback

The rollback path is the inverse of deploy:

| Original action | Rollback action |
|---|---|
| Added a new policy cartridge | Delete or rename the YAML out of `cartridges/lens/`. |
| Edited a policy cartridge | Restore the prior file (git revert, file backup, or config-management redeploy). |
| Disabled a policy cartridge | Move the file back under `cartridges/lens/<policy_type>/`. |

The next scan run after rollback uses the restored file. No process
restart is required.

Findings already persisted with the rolled-back severity remain in the
database with their original severity until they are re-emitted by a
subsequent scan. That is by design — the row is the event record, not a
live mirror of the cartridge.

## Common failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Scan fails with `CartridgeLoadError` in the run's `error_message` | YAML parse error, schema violation, or wrong `policy_type` directory | Re-run Step 1 (pre-flight). |
| Scan succeeds but no findings of the expected kind | Cartridge condition does not match the context the engine builds. Check the `condition` block against the context shape documented at [Policy Cartridges (concepts)](../concepts/policy-cartridges.md#how-a-policy-cartridge-gets-evaluated). | Edit `condition` and re-deploy. |
| Severity on the finding is the legacy Python default, not the YAML value | `decision` block missing or `risk_level` not set | Add `decision.risk_level` and re-deploy. |
| Finding fires for one subject only, not for the population | The relevant data was not loaded into the scan scope | Check `scan_run.scope_*` filters. Cartridges only see the candidates the engine loaded. |
| `405` / `404` on the scan-run endpoints | Wrong API path (current API is `/api/v0/`) | Use `/api/v0/scan-runs/...`. |

## Idempotency

Re-deploying the same YAML file is safe — the loader has no cache to
poison and the dispatcher has no state. Two identical deploys are
indistinguishable from one.

Re-running a scan that already produced findings is also safe: the
ScanEngine deduplicates findings by a 7-column natural key (including
`evidence_hash`); duplicates are reused, not re-inserted.

## Who runs this

Operators or platform engineers with file-system access to the deployment.
This is not an end-user-facing procedure — there is no admin UI for
policy cartridge files today.
