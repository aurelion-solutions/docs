# Write your first pipeline

## What you will build

You will build a two-step pipeline named `orphan_check` that scans for orphan
accounts and terminated-subject findings across all applications. By the end of
this tutorial you will have triggered the pipeline from the CLI, seen
`status: completed`, and read the pipeline event from the event bus.

## Before you start

Three things must be in place:

1. The kernel is running on `http://localhost:8000`. See the kernel
   [quickstart](../index.md) if you have not started it yet.
2. The `al` CLI is installed and on your `PATH`. See
   [CLI — Pipelines](../cli/pipelines.md) for installation details.
3. Your shell has `curl` and `jq` available (used once in Step 6).

## Step 1 — Write the YAML

Create the file `aurelion-kernel/pipelines/orphan_check.yaml` with the
following content:

```yaml
pipeline:
  name: orphan_check
  version: 1
  schema_version: 1

  args:
    type: object
    required: []
    properties:
      application_id:
        type: ["string", "null"]
        format: uuid
      limit:
        type: integer
        minimum: 1
        maximum: 5000
        default: 1000

  steps:
    - name: detect_orphans
      engine: access_analysis.assessment_preview
      action: detect_orphans
      args:
        application_id: "${args.application_id}"
        limit: "${args.limit}"
      requires: []

    - name: detect_terminated
      engine: access_analysis.assessment_preview
      action: detect_terminated
      args:
        application_id: "${args.application_id}"
        limit: "${args.limit}"
      requires: [detect_orphans]
```

Each step calls a registered engine action. `requires:` declares the DAG —
`detect_terminated` only starts after `detect_orphans` finishes. For the full
YAML grammar see [Pipeline YAML](../reference/pipeline-yaml.md).

## Step 2 — Restart the kernel

Pipelines are loaded once at process start. Stop the running kernel with
`Ctrl+C`, then start it again with the same command you used from the kernel
README:

```bash
uv run uvicorn src.runtimes.platform_api.main:app --reload --log-level debug --access-log
```

The `orphan_check` pipeline is now loaded into `app.state.pipelines`. For a
deeper look at how the loader works see
[Pipeline Orchestrator](../concepts/pipeline-orchestrator.md).

## Step 3 — Verify the pipeline is loaded

Run these two commands in order:

```bash
al pipelines list
```

Expected output (one line per pipeline):

```
orphan_check                    v1  steps=2  triggers=0
```

```bash
al pipelines show orphan_check
```

Expected output:

```
name=orphan_check
version=1
steps=2
triggers=0
source=pipelines/orphan_check.yaml
```

Both commands confirm the kernel has the definition in memory.

## Step 4 — Trigger your first run

```bash
al pipelines run orphan_check --args '{}'
```

Expected output:

```
pipeline_run_id=00000000-0000-0000-0000-000000000001
status=pending
version=1
created=true
```

The kernel accepted the run. An executor slot picks it up within a second and
advances it to `running`. For the `pending → running` transition see
[Pipeline Orchestrator](../concepts/pipeline-orchestrator.md).

## Step 5 — Watch it complete

Replace `<RUN_ID>` with the `pipeline_run_id` value printed in Step 4:

```bash
al pipelines runs get <RUN_ID>
```

Expected output:

```
id=00000000-0000-0000-0000-000000000001
pipeline=orphan_check
version=1
status=completed
trigger_source=http
current_step=detect_terminated
started_at=2026-05-11T10:00:00Z
finished_at=2026-05-11T10:00:01Z

detect_orphans    attempt=1  completed  started=2026-05-11T10:00:00Z  finished=2026-05-11T10:00:01Z
detect_terminated attempt=1  completed  started=2026-05-11T10:00:01Z  finished=2026-05-11T10:00:01Z
```

The run finished. Both steps returned empty `findings: []` because there is no
application data in a fresh kernel — that is the expected outcome of this
tutorial, not an error.

## Step 6 — Read the events

```bash
curl -s "http://localhost:8000/api/v0/events?routing_key=pipeline.run.completed&limit=1" \
  | jq '.[0]'
```

Expected response shape:

```json
{
  "event_id": "00000000-0000-0000-0000-000000000002",
  "event_type": "pipeline.run.completed",
  "correlation_id": "00000000-0000-0000-0000-000000000003",
  "causation_id": "00000000-0000-0000-0000-000000000001",
  "payload": {
    "pipeline_run_id": "00000000-0000-0000-0000-000000000001",
    "pipeline_name": "orphan_check",
    "pipeline_version": 1,
    "status": "completed"
  }
}
```

Every status transition emits an event on `aurelion.events`. This is how
Engineering Studio and external observers track the pipeline lifecycle. For the
full event catalogue see [Pipeline Events](../reference/pipeline-events.md).

## Where to go next

- [Pipeline YAML](../reference/pipeline-yaml.md) — full YAML grammar, triggers, templating, and the JSON Schema source.
- [Pipeline Runs API](../reference/pipeline-runs-api.md) — the REST shape behind every `al` command you ran.
- [Pipeline Orchestrator](../concepts/pipeline-orchestrator.md) — how the kernel loads, executes, and recovers pipeline runs.
- [Add an engine action](../guides/add-engine-action.md) — when you want to add a new step type to an engine slice.
