# Action

The controlled vocabulary of normalized access operations. Reference data — seeded by migration, not modified at runtime. Handlers and normalizers must map source-specific verbs to these slugs.

## Seeded vocabulary

| Slug | Meaning |
|---|---|
| `read` | Observe a resource without modifying it |
| `write` | Modify or create a resource |
| `execute` | Run or trigger a resource (job, script, function) |
| `approve` | Grant or authorise access |
| `admin` | Full administrative control |
| `use` | Consume or utilise without full read/write semantics |
| `own` | Ownership-level access; supersedes all other actions |

## API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/actions` | List all actions |
| `GET` | `/api/v0/actions/{slug}` | Get by slug |

Read-only. No create, update, or delete.

## CLI

| Command | Description |
|---|---|
| `al inventory actions list` | List all actions |
| `al inventory action <slug>` | Get by slug (e.g. `al inventory action read`) |
