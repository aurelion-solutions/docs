# Engineering Studio — Commands and Views

Reference catalog of activity-bar surfaces and contributed commands shipped
by the Engineering Studio VS Code extension. For the configuration
reference, see [Engineering Studio — Configuration](engineering-studio-configuration.md).

The extension contributes one activity-bar container (**Aurelion**) hosting
several tree views, plus a status bar item and a set of commands.

## Applications view

Lists applications returned by `GET /api/v0/applications`. Each application
node expands to show its matching connector instances
(`GET /api/v0/applications/{id}/matching-connector-instances`), with their
`instance_id`, tag set, and online status.

Item context menu:

- **Focus Application…** — reveals and selects the application node (also reachable from the command palette as `Aurelion: Reveal applications view`).
- **Aurelion: Show logs for application…** — opens a log stream tab.
- **Aurelion: Toggle log streaming for application** — starts or stops polling for a given application without opening a new tab.
- **Aurelion: Refresh this application** — refreshes a single application row.
- On a connector-instance node: **Copy Connector Instance Id** — writes the `instance_id` to the clipboard.

View title actions:

- **Aurelion: Refresh applications** — full reload of the tree.

## Inventory view

A read-only registry of inventory categories. Categories lazy-load on first
expand.

Shipped categories:

- **Customers** — lists customers from `GET /api/v0/customers`. Label: `external_id`. Description: `plan_tier`. Tooltip: `customer_id`, `tenant_id`, `mfa_enabled`, `is_locked`, `updated_at`.
- **Access State** — multi-tab view of the access surface. See [Access State multi-tab category](#access-state-multi-tab-category) below.
- **Account State** — multi-tab view of accounts. See [Account State multi-tab category](#account-state-multi-tab-category) below.

Creating, updating, and deleting inventory records is done through the REST
API or the CLI — no webview forms or quick-pick mutations are exposed from
the Inventory view.

### Access State multi-tab category

The Studio exposes the access surface as a single `accessState` node with three tabs framed by the declarative-planning lifecycle:

| Tab | Source | What it shows |
|---|---|---|
| **List** | `GET /api/v0/access-facts` | Effective access facts — what subjects currently hold |
| **Incoming** | `GET /api/v0/inventory-reconciles/delta-items?entity_type=access_fact&status!=unchanged` | Pending delta items from reconciliation runs — what the lake says should change |
| **Outgoing** | `GET /api/v0/plans/items?execution_status=proposed,executing` | Plan items the executor is about to apply (or has just started applying) |

Columns shared across tabs: **Application · Op · Subject · Target · Change · Time**. The columns are populated from server-side display fields (`application_code`, `subject_display`, `account_display`, `resource_display`, `change_summary`) — no client-side resolution needed.

The node renders a diff-count badge driven by the cross-run `.../delta-items/count` and `/plans/items/count` endpoints — the badge fires when there is incoming or outgoing work pending for the visible scope.

### Account State multi-tab category

`accounts` became a multi-tab `accountState` node on the same Incoming / List / Outgoing model:

| Tab | Source | What it shows |
|---|---|---|
| **List** | `GET /api/v0/accounts` | All active accounts (with H5 display fields) |
| **Incoming** | `GET /api/v0/inventory-reconciles/delta-items?entity_type=account&status!=unchanged` | Pending account-level delta items |
| **Outgoing** | `GET /api/v0/plans/items?kind=account_create,account_invite,account_activate,account_suspend,account_disable` | Plan items whose `kind` is in the account family |

Same column layout as Access State.

View actions:

- **Aurelion: Refresh inventory** — clears every category's cache.
- **Refresh** (category context menu) — reloads a single category; also reachable via the inline retry action on a failed-to-load placeholder.

## Pipelines view

Tree of run-status buckets that frames the pipeline orchestrator surface
in the sidebar. Clicking a status node opens a live runs-list detail
panel. Clicking the **Definitions** node opens a list of all registered
pipeline templates; from that list a row click drills into a single
definition. The **Definitions** node also anchors the **Trigger pipeline
run...** context-menu action (see
[Triggering a pipeline run](#triggering-a-pipeline-run)).

Tree contents (fixed order):

- **Running** — runs in flight.
- **Pending** — queued runs not yet started.
- **Awaiting Event** — runs paused waiting for an external event.
- **Failed** — runs that ended in a failure state.
- **Failed (Timeout)** — runs that exceeded their deadline.
- **Cancelled** — runs ended by cancellation.
- **Completed** — runs that finished successfully.
- **Definitions** — UI-only bucket that hosts pipeline templates.
  Clicking the node opens the [Definitions list panel](#definitions-list-panel);
  right-click to reach the **Trigger pipeline run...** action.

The first seven keys map 1:1 onto the `PipelineRunStatus` enum exposed by
the kernel; the `cancelling` transient state is intentionally folded into
**Running**. **Definitions** has no enum counterpart and exists as a
navigation hook into the pipeline-template catalog.

### Runs-list detail panel

Clicking any of the seven status nodes opens a `WebviewPanel` titled
`Pipeline runs · <Status>` backed by
`GET /api/v0/pipeline-runs?status=<status>&limit=100`. The panel polls
on the cadence set by `aurelion.engineeringStudio.eventsRefreshSeconds`
(default `5s`).

Columns, in order:

| Column | Source field | Notes |
|--------|--------------|-------|
| Pipeline | `pipeline_name` | |
| Status | `status` | Rendered as a status badge. |
| Started | `started_at` | ISO 8601 timestamp; empty for runs that have not started. |
| Current Step | `current_step` | Empty when the run has no active step. |
| Duration | derived from `started_at`/`finished_at` | `Xs` or `Xm Ys`. Renders `…` while a run is still in flight (no wall-clock reads in the renderer — duration is deterministic). |
| Created | `created_at` | ISO 8601 timestamp. |

Drift from the design intent: `worker_id` is not part of
`PipelineRunSummary` on the wire, so the panel surfaces `created_at` in
its place. Resolving worker identity would require N+1 fetches and is
out of scope for this view.

#### Row actions

Each row exposes per-run actions whose visibility is driven by the run's
current `status`:

| Action | Visible when status is… | Hidden when status is… |
|--------|-------------------------|------------------------|
| **Cancel** | `pending`, `running`, `awaiting_event` (non-terminal) | `cancelling`, `completed`, `failed`, `failed_timeout`, `cancelled` |
| **Retry** | `completed`, `failed`, `failed_timeout`, `cancelled` (terminal) | `pending`, `running`, `awaiting_event`, `cancelling` |

The transient `cancelling` status shows neither button — the run is
already on its way out and a retry from this state is rejected by the
kernel with `409`.

Clicking either button opens a modal confirmation (`Cancel run?` /
`Retry run?`) before any HTTP call. Confirming **Cancel** issues
`POST /api/v0/pipeline-runs/{run_id}/cancel`; confirming **Retry**
issues `POST /api/v0/pipeline-runs/{run_id}/retry`.

The panel does not apply optimistic UI: after a successful action the
list is refreshed from the kernel and the row reflects the authoritative
new status. Kernel rejections (typically `409` when the run has moved
state under you between render and click) surface as error toasts and
leave the panel state unchanged.

#### Row click — open run detail

Clicking anywhere on a row outside the action buttons opens a read-only
run-detail panel for that run (see below). Action buttons stop click
propagation, so clicking **Cancel** or **Retry** does not also open the
detail panel.

### Run-detail panel

Opened by clicking a row in the runs-list panel. Title:
`Pipeline run · <pipeline_name>`. Backed by
`GET /api/v0/pipeline-runs/{run_id}` and polled on the cadence set by
`aurelion.engineeringStudio.eventsRefreshSeconds` (default `5s`).

Polling is **status-aware**: when the run reaches a terminal status
(`completed`, `failed`, `failed_timeout`, `cancelled`) the panel stops
polling. Reopen the panel to force a refresh after a manual retry.

#### Header section

A two-column key/value table with the run's top-level fields. Rows, in
order:

| Field | Source | Notes |
|-------|--------|-------|
| `pipeline_name` | `pipeline_name` | |
| `version` | `pipeline_version` | Rendered as a badge. |
| `status` | `status` | Rendered as a status badge. |
| `trigger_source` | `trigger_source` | `http`, `event`, `retry`, etc. |
| `current_step` | `current_step` | Empty when the run has no active step. |
| `started_at` | `started_at` | ISO 8601; empty for runs that have not started. |
| `finished_at` | `finished_at` | ISO 8601; empty until terminal. |
| `created_at` | `created_at` | ISO 8601. |
| `updated_at` | `updated_at` | ISO 8601. |
| `error` | `error` | Empty unless the run is in a failure state. |
| `content_hash` | `content_hash` | Hash of the pipeline definition snapshot used by this run. |
| `args` | `args` | Trigger arguments rendered as single-line JSON. |

Drift from the design intent: `worker_id` is not part of
`PipelineRunDetail` on the wire either, so it is not surfaced. Resolving
the owning worker would require an out-of-scope join against the
worker-heartbeat table.

#### Steps section

A six-column table listing every step-run row for the run, in kernel
order (no client-side sort). One row per **attempt** — retried runs
carry forensic `aborted` rows from prior attempts alongside the active
attempt.

| Column | Source | Notes |
|--------|--------|-------|
| Step | `step_name` | |
| Attempt | `attempt` | Rendered as a badge. |
| Status | `status` | One of `pending`, `running`, `awaiting_event`, `completed`, `failed`, `failed_timeout`, `aborted`, `cancelled`. Rendered as a status badge. |
| Started | `started_at` | ISO 8601 or empty. |
| Finished | `finished_at` | ISO 8601 or empty. |
| Error | `error` | Empty unless the step is in a failure state. |

When the run has no step rows yet (typical for a freshly-created run
before the orchestrator has materialised the first step), the table
renders a single placeholder row labelled **No steps yet**.

Clicking a step row opens a read-only step-detail panel for that step
attempt (see below).

#### Steps DAG (run view)

Below the Steps table the panel renders a directed-acyclic graph of
the run. Topology comes from the pipeline definition (fetched in
parallel with the run detail via `GET /api/v0/pipelines/{name}`); node
colours come from the per-step `StepRunStatus`. The DAG and the Steps
table are complementary — the table keeps attempt counts and
timestamps, the DAG conveys live status at a glance.

If the parallel definition fetch fails (for example, the definition was
deleted between run start and panel open), the panel renders without
the DAG and logs the failure to the **Aurelion · Extension** output
channel; the Steps table remains.

Node border styling, by `StepRunStatus`:

| Status | Border |
|--------|--------|
| `pending` (or step in definition not yet executed) | dimmed grey, 60% opacity |
| `running` | blue, 3px |
| `awaiting_event` | amber, 2px, dashed |
| `completed` | green, 2px |
| `failed`, `failed_timeout` | red, 3px |
| `aborted`, `cancelled` | grey, 50% opacity, dotted |

When the run executed against a pipeline snapshot whose `content_hash`
no longer matches the current definition, the DAG handles drift
gracefully:

- Steps present in the definition but not in the run render as
  pending (no `status` set on the node).
- Steps present in the run but absent from the current definition are
  omitted from the graph and surfaced as warnings on the **Aurelion ·
  Extension** output channel
  (`step '<name>' present in run but not in current definition (content_hash drift)`).

Clicking a node opens the same args panel below the graph as in the
definition view; the title reads `Args for: <step name>` and the body
shows `{ args, result, error, status, attempt, started_at,
finished_at }`. The body is lazy-loaded via
`GET /api/v0/pipeline-runs/{run_id}/steps/{step_id}` on first click for
that node; the panel shows `Loading...` until the response arrives.
Clicking a pending node (no step_run row yet) shows the pending
sentinel immediately without an HTTP call.

Polling refresh keeps both the Steps table and the DAG in sync; node
colours flip as the run progresses. When the run reaches a terminal
status, polling stops and the final DAG state persists until the panel
is closed.

### Step-detail panel

Opened by clicking a step row in the run-detail panel. Title:
`Pipeline step · <step_name>`. Backed by
`GET /api/v0/pipeline-runs/{run_id}/steps/{step_name}`.

Polling is **off** — this panel is a read-only deep view of a single
step attempt. Close and reopen the panel (or refresh the parent run
panel and click again) to fetch the latest state.

The panel is routed independently of the run-detail panel: its routing
key is carried on `meta.routingKey`, kept distinct from the section
title so that opening a step-detail panel does not collide with or
replace the parent run-detail panel.

#### Header section

A two-column key/value table with the step attempt's top-level fields.
Rows, in order:

| Field | Source | Notes |
|-------|--------|-------|
| `step_name` | `step_name` | |
| `status` | `status` | Rendered as a status badge. |
| `attempt` | `attempt` | Rendered as a badge. |
| `started_at` | `started_at` | ISO 8601; empty if the step has not started. |
| `finished_at` | `finished_at` | ISO 8601; empty until the attempt is terminal. |
| `worker_id` | `worker_id` | Identifier of the worker that picked up this attempt; empty when the attempt has not been claimed. |
| `error` | `error` | Empty unless the attempt is in a failure state. |
| `result_summary` | `result_summary` | Compact summary of the step's result payload. Empty until the attempt finishes. |
| `args` | `args` | Step arguments rendered as single-line JSON. |

View title actions:

- **Aurelion: Refresh Pipelines** — re-renders the tree. Open detail
  panels keep polling independently.

### Definitions list panel

Opened by clicking the **Definitions** tree node. Title:
`Pipeline definitions`. Backed by `GET /api/v0/pipelines`. The panel is
not polled — definitions change rarely; reopen the panel (or use
**Aurelion: Refresh Pipelines**) to fetch a fresh list.

Columns, in order:

| Column | Source field | Notes |
|--------|--------------|-------|
| Name | `name` | |
| Version | `version` | Rendered as a badge. |
| Schema | `schema_version` | Rendered as a badge. |
| Steps | derived — `steps.length` | Integer step count. |
| Triggers | derived — `triggers.length` | Integer trigger count; `0` when the definition has no triggers. |

Clicking a row opens the [Definition detail panel](#definition-detail-panel)
for that pipeline. Row clicks are the only interaction surface — no
row-level action buttons live in this panel.

### Definition detail panel

Opened by clicking a row in the Definitions list panel. Title:
`Pipeline definition · <name>`. Backed by `GET /api/v0/pipelines/{name}`.
Polling is **off** — the panel is a read-only deep view of a single
definition.

#### Header section

A two-column key/value table with the definition's top-level fields:

| Field | Source | Notes |
|-------|--------|-------|
| `name` | `name` | |
| `version` | `version` | Rendered as a badge. |
| `schema_version` | `schema_version` | Rendered as a badge. |

#### Triggers section

A table of every trigger declared on the definition. When the definition
has no triggers the section renders a placeholder row labelled
**No triggers**.

| Column | Source | Notes |
|--------|--------|-------|
| Type | `type` | `event`, `cron`, etc. Rendered as a badge. |
| Detail | derived | Single-line summary of trigger-specific config (e.g. event name, cron expression). |

#### Steps DAG

An interactive directed-acyclic graph of every step declared on the
definition, rendered with `cytoscape.js` + `cytoscape-dagre` (top-down
layout). Each node is laid out from the step's `requires` edges; dangling
`requires` are skipped and reported on the webview console. When the
definition has no steps, the graph is hidden and a **No steps**
placeholder is shown instead.

Each node renders on two lines:

- Line 1 — step `name`.
- Line 2 — `<engine>.<action>` for engine-call steps, `wait_for_event`
  for park steps, or `<unknown>` when the step shape matches neither.

`wait_for_event` and `<unknown>` nodes are border-highlighted (warning
and error colours respectively) so unknown step kinds remain visible
rather than silently hidden.

Clicking a node opens a panel **below the graph** (full width) titled
`Args for: <step name>` showing that step's full `args` as
pretty-printed JSON. The DAG is read-only — nodes can be dragged for
layout tweaks, but no edit, create, or delete actions are exposed.

Layout details: dagre top-down, `ranker: tight-tree`, deterministic
across polling refreshes. Edges are 2px with `triangle-backcurve`
arrowheads. First render eases in over 200ms; subsequent re-renders
(triggered by polling) are instantaneous to avoid jitter. Hovering a
node thickens its border and switches the cursor to a pointer.

### Triggering a pipeline run

Right-click the **Definitions** node in the Pipelines view and choose
**Aurelion: Trigger pipeline run...** to open the trigger form.

The form loads the list of available pipelines from
`GET /api/v0/pipelines` and presents:

- A **Pipeline** dropdown pre-populated with pipeline names.
- An **Args** textarea for a raw JSON object (e.g. `{"env": "prod"}`).
  Empty input or non-object JSON is rejected client-side before any HTTP
  call is made.

Clicking **Trigger run** issues `POST /api/v0/pipeline-runs`. On success
(201 Created or 200 OK for an idempotent re-hit) the form closes, a
success toast appears, and the Pipelines tree refreshes. Validation errors
returned by the kernel (HTTP 422) are rendered verbatim inside the form
without closing it, so the args can be corrected and resubmitted.

See [Pipeline Runs API](pipeline-runs-api.md) for the REST surface.

## Pipeline YAML editing

Engineering Studio provides autocomplete and structural validation for
pipeline YAML files. The schema is sourced in two tiers:

1. **Bundled snapshot** (offline fallback) —
   `schemas/aurelion-pipeline.schema.json` ships with the extension and
   covers the structural grammar (`name`, `version`, `schema_version`,
   `args`, `triggers`, `steps`, builtin step types). Available without a
   running kernel.
2. **Live merge** — on activation and whenever
   `aurelion.engineeringStudio.apiBaseUrl` changes, the extension fetches
   `GET /.well-known/pipeline-schema.json` from the kernel and overrides
   the bundled snapshot. The live schema includes the per-action
   `with:` argument schemas from the kernel's in-memory action
   registry, so autocomplete reflects what the running kernel can
   actually execute.

The schema is applied to any YAML file matching the glob
`**/pipelines/*.yaml` or `**/pipelines/*.yml` — covers
`aurelion-kernel/pipelines/`, monorepo sub-paths such as
`myservice/pipelines/foo.yaml`, or any directory literally named
`pipelines/` in the workspace.

### Schema registration

Schema delivery to the YAML editor goes through the
[Red Hat YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)
(`redhat.vscode-yaml`), declared as an `extensionDependencies` entry so
VS Code installs it automatically alongside Engineering Studio.

Engineering Studio registers a schema contributor against the virtual
URI `aurelion-pipeline://merged/pipeline.schema.json`. The bundled
schema is served from memory; when a live override is cached, the same
URI returns the merged document instead. The YAML extension is
notified via `notifySchemaChanged` so open editors pick up the new
schema without reload.

The contributor is registered through a defensive 4-step shape-check
ladder. If any rung fails, the contributor is a silent no-op — YAML
editing continues to work without Aurelion-specific validation:

| Rung | Check | Failure log token |
|------|-------|-------------------|
| 1 | `vscode.extensions.getExtension("redhat.vscode-yaml")` returns a value | `pipeline_schema.yaml_extension_missing` |
| 2 | The extension's `activate()` returns an object | `pipeline_schema.yaml_exports_missing` |
| 3 | Exports include a callable `registerContributor` function | `pipeline_schema.yaml_registerContributor_missing` |
| 4 | `registerContributor(...)` invocation | logs `pipeline_schema.live_override_applied` or `pipeline_schema.fallback` on subsequent fetches |

`notifyChanged()` calls that arrive before the contributor is wired
are buffered behind a pending flag and replayed once registration
completes.

### Live fetch behaviour

| Aspect | Behaviour |
|--------|-----------|
| Endpoint | `GET /.well-known/pipeline-schema.json` (unversioned by design — never under `/api/v0/`) |
| Trigger | Extension activation; every change to `aurelion.engineeringStudio.apiBaseUrl` |
| Timeout | 5 seconds; aborted via `AbortController` |
| Result | Discriminated union (`ok` with parsed schema and byte size, or `fail` with a `reason` token) |
| Fallback | Bundled schema remains active when the fetch fails, times out, or returns a non-object body |
| Logging | `apiBaseUrl` is redacted (userinfo stripped) before being written to the **Aurelion · Extension** output channel |

### Failure tokens

When a fetch fails, the channel records `pipeline_schema.fallback
reason=<token>`. Tokens surface on the output channel only and are not
user-facing UI:

- `network_error` — connection refused, DNS failure, abort.
- `timeout` — the 5-second deadline elapsed.
- `bad_status` — kernel returned non-2xx.
- `bad_payload` — body was not a JSON object.

When the fetch succeeds the channel records
`pipeline_schema.live_override_applied apiBaseUrl=<redacted>
sizeBytes=<N>` and the cache flips to the live schema.

## Log streaming

Invoking **Aurelion: Show logs for application…** either from a tree item
or the command palette opens a virtual document backed by the
`/api/v0/log-buffer` endpoint. The document appends new events on each
tick of `logStreamPollMs`. The tab is read-only; close it to stop
rendering, or use **Toggle log streaming** to pause without closing.

If the tree refreshes while the quick-pick is open and the selected
application is no longer present, the command exits with an informational
message rather than opening a stale stream.

## Status bar

A status bar item on the left shows `N / M connectors online` across all
applications. Clicking it runs **Aurelion: Reveal applications view**.
When the last refresh failed, the item renders in a warning state; the
underlying error is in the **Aurelion · Extension** output channel.

## Commands

| Command id | Palette title |
|------------|---------------|
| `aurelion.refreshApplications` | Aurelion: Refresh applications |
| `aurelion.openLogs` | Aurelion: Show logs for application… |
| `aurelion.toggleLogStreaming` | Aurelion: Toggle log streaming for application |
| `aurelion.focusApplicationsView` | Aurelion: Reveal applications view |
| `aurelion.refreshInventory` | Aurelion: Refresh inventory |
| `aurelion.focusInventoryView` | Aurelion: Reveal inventory view |
| `aurelion.refreshPipelines` | Aurelion: Refresh Pipelines |

`aurelion.refreshApplication`, `aurelion.refreshInventoryCategory`,
`aurelion.copyInstanceId`, `aurelion.focusApplication`,
`aurelion.cancelPipelineRun`, `aurelion.retryPipelineRun`, and
`aurelion.triggerPipelineRun` are internal — bound to webview row
actions or tree context menus and hidden from the command palette via
`"when": "false"`. The two pipeline-run row commands
(`cancelPipelineRun`, `retryPipelineRun`) are invoked from the
runs-list detail panel only and require a `run_id` argument.
`triggerPipelineRun` is bound to the **Definitions** node context
menu in the Pipelines view; it takes no arguments.
