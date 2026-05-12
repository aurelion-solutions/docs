# Connector Descriptor

A connector descriptor is the machine-readable capability declaration that a
connector process attaches to its registration message. The `access_plan` engine
reads the descriptor to determine what operations the connector supports, which
account state transitions are valid, and how to build a dependency DAG.

Source of truth: `aurelion-kernel/src/platform/connectors/registration_schemas.py`

---

## Top-level shape

```yaml
operations:
  grant_role:
    dependency_rules:
      - kind: account
        status: [active]
  account_create: {}
  account_invite: {}
  account_activate: {}
  account_suspend: {}
  account_disable:
    cascades:
      before_disable:
        - kind: revoke_role
        - kind: group_remove

account_status:
  transitions:
    - from: not_exists
      to: invited
    - from: invited
      to: active
    - from: active
      to: suspended
    - from: suspended
      to: active
    - from: active
      to: disabled

verify_fact_supported: true

supported_fact_kinds:
  - account
  - role
  - group
  - entitlement
```

---

## `operations`

A map of operation kind (string) to an `OperationDescriptor` object.

Declaring an operation in `operations` signals that this connector
can perform it. The `access_plan` engine only emits plan items for
operations that appear in the connector's `operations` map.

### `operations[].dependency_rules`

Zero or more rules that must be satisfied before this operation can run.
Each rule specifies what must be true about another entity in the system
at the time of DAG execution.

```yaml
operations:
  grant_role:
    dependency_rules:
      - kind: account
        status: [active]
        application: null   # null = same application as the item being planned
```

| Field | Type | Notes |
|---|---|---|
| `kind` | string | The kind of entity required (`account`, `role`, `group`, `entitlement`) |
| `status` | string[] | List of acceptable statuses for that entity. The DAG resolver checks the current state at plan-build time. |
| `application` | UUID \| null | Target application UUID for a cross-application dependency. `null` means the same application as the plan item. |

**Cross-application dependencies**

A `grant_role` in Slack may require an active account in Google Workspace:

```yaml
operations:
  grant_role:
    dependency_rules:
      - kind: account
        status: [active]
        application: "google-workspace-app-uuid"
```

The `access_plan` DAG resolver handles cross-application references the same
way as within-application dependencies — it looks up the current account
state in `accounts` for the specified `application` and generates an
`account_create` or `account_activate` plan item for that application if the
state requirement is not already satisfied.

---

## `account_status.transitions`

The list of valid account state transitions for this connector. The
`access_plan` engine uses this to resolve the concrete operation kind needed
to reach a target state from the current state.

```yaml
account_status:
  transitions:
    - from: not_exists
      to: invited
    - from: invited
      to: active
    - from: active
      to: suspended
    - from: suspended
      to: active
    - from: active
      to: disabled
```

`not_exists` is a sentinel value meaning the account row is absent from
the `accounts` table (not an enum value in the database).

The resolver walks the transition graph to find the shortest path from
current state to the required state. If no path exists, the plan item is
marked `unsatisfiable` and the plan is flagged.

---

## `cascades`

Defines automatic cascade operations that must precede certain state changes.

Currently only `account_disable` is cascadable.

```yaml
account_status:
  ...

operations:
  account_disable:
    cascades:
      before_disable:
        - kind: revoke_role
        - kind: group_remove
        - kind: entitlement_detach
```

When the DAG resolver encounters an `account_disable` item, it synthesizes
additional revoke/remove items for every active role, group membership, and
entitlement of that account in that application. The synthesized items are
added to the plan with `account_disable` as their dependent — they must
complete before the disable executes.

If a revoke or remove item is already present in the plan (because the diff
produced it independently), no duplicate is added.

---

## `verify_fact_supported`

```yaml
verify_fact_supported: true
```

When `true`, the connector exposes a `verify_fact` primitive that
`access_apply` calls:

- **Preflight** — before invoking the connector, to detect "already done"
  states (idempotency / external race).
- **Post-apply** — after the connector call completes, to confirm the change
  took effect.

When `false`, `access_apply` skips both verification calls. Items complete
with `status = done` solely on the basis of a successful connector call,
without post-apply confirmation.

Setting `verify_fact_supported: false` is acceptable for connectors that
implement idempotency internally, but reduces the double-protection offered
by the preflight path.

---

## `supported_fact_kinds`

```yaml
supported_fact_kinds:
  - account
  - role
  - group
  - entitlement
```

The list of access-fact kinds the connector can manage. The `access_plan`
engine uses this list to gate plan-item generation — it will not generate a
plan item for a fact kind the connector does not declare support for.

---

## Full YAML example — flat connector

```yaml
# Flat connector: plain role grants, no invite flow
operations:
  account_create:
    dependency_rules: []
  account_activate:
    dependency_rules: []
  account_suspend:
    dependency_rules: []
  account_disable:
    dependency_rules: []
    cascades:
      before_disable:
        - kind: revoke_role
  grant_role:
    dependency_rules:
      - kind: account
        status: [active]
  revoke_role:
    dependency_rules: []

account_status:
  transitions:
    - from: not_exists
      to: active
    - from: active
      to: suspended
    - from: suspended
      to: active
    - from: active
      to: disabled

verify_fact_supported: true

supported_fact_kinds:
  - account
  - role
```

---

## Full YAML example — hierarchical connector (invite flow + cross-app dep)

```yaml
# Hierarchical connector: invite flow, nested groups, cross-app dependency
operations:
  account_create:
    dependency_rules: []
  account_invite:
    dependency_rules: []
  account_activate:
    dependency_rules:
      - kind: account
        status: [invited]
  account_suspend:
    dependency_rules:
      - kind: account
        status: [active]
  account_disable:
    dependency_rules:
      - kind: account
        status: [active, suspended]
    cascades:
      before_disable:
        - kind: revoke_role
        - kind: group_remove
        - kind: entitlement_detach
  grant_role:
    dependency_rules:
      - kind: account
        status: [active]
      # Requires active account in another application
      - kind: account
        status: [active]
        application: "google-workspace-app-uuid"
  revoke_role:
    dependency_rules: []
  group_add:
    dependency_rules:
      - kind: account
        status: [active]
  group_remove:
    dependency_rules: []
  entitlement_attach:
    dependency_rules:
      - kind: account
        status: [active]
  entitlement_detach:
    dependency_rules: []

account_status:
  transitions:
    - from: not_exists
      to: invited
    - from: invited
      to: active
    - from: active
      to: suspended
    - from: suspended
      to: active
    - from: active
      to: disabled
    - from: suspended
      to: disabled

verify_fact_supported: true

supported_fact_kinds:
  - account
  - role
  - group
  - entitlement
```

---

## Registration

Descriptors are attached to the connector registration message:

```json
{
  "instance_id": "my-connector-1",
  "connector_type": "my_system",
  "tags": ["my_system"],
  "descriptor": { "...": "..." }
}
```

`descriptor` is optional for backward compatibility. Connectors that omit it
have `null` stored in `connector_instances.descriptor` and will not be
selected for plan execution — `access_plan` requires a descriptor to build
the DAG.

The descriptor is stored as-is in `connector_instances.descriptor` (JSONB).
It is not validated at registration time beyond basic JSON parsing; schema
validation happens when `access_plan` reads and parses it with
`ConnectorCapabilityDescriptor`.

---

## Source of truth

- `aurelion-kernel/src/platform/connectors/registration_schemas.py`
- `aurelion-kernel/src/platform/connectors/mock_connector.py` (flat example)
- `aurelion-kernel/src/platform/connectors/mock_connector_hierarchical.py`
  (hierarchical example)
