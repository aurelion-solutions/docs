# Access Usage Fact

Telemetry records showing whether and how often an access grant was actually exercised. Each record covers one observation window for one AccessFact. Append-only — no update or delete.

## Key fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `access_fact_id` | UUID | FK to AccessFact |
| `last_seen` | datetime | Last observed exercise within the window |
| `usage_count` | int | Exercise count in the window |
| `window_from` | datetime | Window start (inclusive) |
| `window_to` | datetime | Window end (exclusive, nullable = open-ended) |

Unique on `(access_fact_id, window_from, window_to)` — duplicate ingests return 409.

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/access-usage-facts` | List, filter by `access_fact_id`, `subject_id`, `resource_id`, `since` |
| `GET` | `/api/v0/access-usage-facts/{id}` | Get by ID |
| `POST` | `/api/v0/access-usage-facts` | Ingest a new window |

## CLI

| Command | Description |
|---|---|
| `al inventory usage-facts list` | List all usage facts |
| `al inventory usage-facts list --access-fact <id>` | Filter by fact |
| `al inventory usage-facts list --subject <id>` | Filter by subject (indirect) |
| `al inventory usage-facts list --since <iso>` | Filter by last_seen |
| `al inventory usage-facts get <id>` | Get by ID |
| `al inventory usage-facts create --access-fact <id> --last-seen <iso> --usage-count <n> --window-from <iso>` | Ingest window |
