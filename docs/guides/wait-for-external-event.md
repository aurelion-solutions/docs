# How to wait for an external event in a pipeline

Use this guide when a pipeline step needs to pause and resume only after an
external signal arrives — a human approval, a webhook callback from a
downstream system, or a sibling pipeline signalling completion.

## What you need

- The **event type** and **routing key** of the signal you want to wait for.
  Both are defined by whatever system publishes the event.
- A payload shape you can write a matcher expression for.
- An `expires_at` strategy: either an `expires_in` relative duration (e.g.
  `"PT4H"` for four hours) or an absolute ISO-8601 timestamp that exceeds the
  upstream system's worst-case SLA.

## When to use `wait_for_event`

Good fits:

- **Human-in-the-loop** — a manager approves or rejects an access request by
  publishing an event after acting in the UI.
- **External callback** — a third-party system sends a webhook that the
  connector translates to a bus event.
- **Sibling pipeline** — a downstream pipeline emits an event from its
  `service.py` when it completes a sub-task.

Not a fit:

- **Timed delay** ("wait 30 minutes then continue") — there is no `sleep` step
  type.  For fixed-interval delays, model the downstream work as a separate
  pipeline triggered by a schedule.

## Declare the step

Add a `wait_for_event` step to your pipeline YAML:

```yaml
steps:
  - name: await_approval
    type: wait_for_event
    # The routing key on aurelion.events that carries this signal.
    event_type: iga.access_request.approved
    # Subset-containment matcher: the event payload must contain these fields.
    match:
      request_id: "{{ run.args.request_id }}"
    # Relative timeout from the moment the step is reached.
    expires_in: "PT8H"
    # On match, proceed to the next step by name.
    next: provision_access

  - name: provision_access
    type: engine_call
    engine: access_apply
    action: apply_grant
    args:
      request_id: "{{ run.args.request_id }}"
    next: done

  - name: done
    type: terminal
```

Full YAML grammar for `wait_for_event` — including all fields and valid
`expires_at` vs `expires_in` forms — is in
[`../reference/pipeline-yaml.md#wait_for_event`](../reference/pipeline-yaml.md#wait_for_event).

## How matching works

When a bus event arrives, the matcher checks whether the configured `match`
expression is a **subset** of the event payload.  Every key-value pair in
`match` must be present and equal in the event payload for the step to wake up.
Extra fields in the payload are ignored.

Nested structures follow the same containment rule recursively.  There is a
specific caveat for list values — an exact-list match is required, not
containment within a list.  See
[`../reference/pipeline-yaml.md#matcher-semantics`](../reference/pipeline-yaml.md#matcher-semantics)
for the precise rules before writing matchers over nested arrays.

For the conceptual model of how events flow through the bus and resolve
waiters, see
[`../concepts/event-flow.md#as-consumer-wait_for_event-waiters`](../concepts/event-flow.md#as-consumer-wait_for_event-waiters).

## How timeout works

If no matching event arrives by the `expires_at` deadline, the beat sweep
transitions the step to `failed_timeout` and fails the parent run with
`error='event_timeout'`.  The run lands in the `failed` terminal status.

From there you have two options:

- Fix the upstream signal and retry the run (see
  [`./retry-failed-run.md`](./retry-failed-run.md)).
- Increase the `expires_in` duration in the pipeline definition if the timeout
  was too short for the upstream system's SLA.

The `pipeline.run.failed` event emitted on timeout is described in
[`../reference/pipeline-events.md#run-level-events`](../reference/pipeline-events.md#run-level-events).

## How to verify the parked run

Once a run reaches the `await_approval` step, its status changes to
`awaiting_event`.  The run is parked in the database and holds no executor
slot.

```bash
curl -s http://localhost:8000/api/v0/pipeline-runs/00000000-0000-0000-0000-000000000001 | jq '{status, worker_id, current_step}'
```

Expected output:

```json
{
  "status": "awaiting_event",
  "worker_id": null,
  "current_step": "await_approval"
}
```

`worker_id: null` confirms the run is not consuming an executor slot while it
waits.

## How to fire the matching event

Any process on the bus can publish a matching event.  Production systems should
emit from their `service.py` via `EventService.emit(...)`.

For ad-hoc testing in a local environment, you can push an event directly with
`rabbitmqadmin`:

```bash
# For testing only — production emits go through service.py
rabbitmqadmin publish \
  exchange=aurelion.events \
  routing_key=iga.access_request.approved \
  payload='{"request_id":"00000000-0000-0000-0000-000000000099","approved_by":"ops@example.invalid"}'
```

The matcher picks up the event, evaluates it against all registered waiters,
and resumes the matching run.

## Common pitfalls

- **Routing key drift** — the event is published on a different routing key
  than the `event_type` in the YAML.  The matcher never sees it, and the run
  times out.  Cross-check the publisher's routing key against the YAML field.
- **Over-tight `match` with lists** — if your matcher includes an array field,
  the matcher requires exact list equality, not containment.  A payload like
  `{"roles": ["admin", "viewer"]}` will NOT match
  `{"roles": ["admin"]}`.  See
  [`../reference/pipeline-yaml.md#matcher-semantics`](../reference/pipeline-yaml.md#matcher-semantics).
- **`expires_at` shorter than upstream SLA** — the run times out before the
  upstream system can respond.  Measure the worst-case response time of the
  external system and add a safety margin.

## See also

- [`../reference/pipeline-yaml.md#wait_for_event`](../reference/pipeline-yaml.md#wait_for_event) — full step grammar
- [`../reference/pipeline-events.md#waiter-resolution`](../reference/pipeline-events.md#waiter-resolution) — events emitted when a waiter resolves or times out
- [`../concepts/event-flow.md`](../concepts/event-flow.md) — how the bus drives waiter resolution end-to-end
- [`../reference/pipeline-yaml.md#matcher-semantics`](../reference/pipeline-yaml.md#matcher-semantics) — containment rules and list caveat
