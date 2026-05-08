# Capability Preview

Pre-flight resolver answering "which capability slugs would these sources grant?" without persisting anything or touching the EAS table. Used by SoD what-if and by callers building hypothetical capability bundles before evaluation.

Pure read. No persistence. No events.

## API

### `POST /api/v0/capability-preview/resolve`

Resolves a list of caller-supplied effective-grant-shaped sources to the distinct, alphabetically sorted set of capability slugs they would grant under the active `CapabilityMapping` and `Capability` tables.

**Request — `ResolveCapabilitiesRequest`:**

| Field | Type | Description |
|---|---|---|
| `sources` | `EffectiveGrantRef[]` | Caller-built grant-shaped references. May be empty. |

**`EffectiveGrantRef` fields:**

| Field | Type | Description |
|---|---|---|
| `application_id` | UUID | Owning application |
| `resource_id` | UUID | Target resource |
| `action_slug` | string | One of the seeded action slugs (`read`, `write`, `execute`, `admin`, ...) |
| `resource_kind` | string | Caller-denormalized resource kind (matches projector matchers) |
| `resource_external_id` | string | Caller-denormalized resource external id |

The reference is intentionally minimal — `subject_id`, `tombstoned_at`, and resource/subject attributes are omitted because slug resolution does not depend on them. Callers may construct hypothetical sources without round-tripping to EAS.

**Response — `ResolveCapabilitiesResponse`:**

| Field | Type | Description |
|---|---|---|
| `capability_slugs` | `string[]` | Distinct, alphabetically sorted capability slug list |

**Example request:**

```json
{
  "sources": [
    {
      "application_id": "00000000-0000-0000-0000-000000000001",
      "resource_id": "00000000-0000-0000-0000-000000000010",
      "action_slug": "admin",
      "resource_kind": "ad_group",
      "resource_external_id": "CN=Admins,OU=Groups,DC=example,DC=com"
    }
  ]
}
```

**Example response:**

```json
{
  "capability_slugs": ["finance.payments.approve", "finance.payments.read"]
}
```

Empty input is valid and returns `{"capability_slugs": []}`.

## Semantics

- The resolver never reads `effective_grants` — it operates exclusively on the caller-supplied sources joined against active `CapabilityMapping` rows.
- Slug output is deduplicated and sorted alphabetically. The order is stable across calls.
- The endpoint never persists, never emits events, and never participates in a transaction.
- Tombstone filtering is the caller's responsibility — the resolver treats every supplied source as live.

## CLI

No CLI surface today. This is a service-internal building block consumed by the SoD what-if endpoint and by future analysis tooling.
