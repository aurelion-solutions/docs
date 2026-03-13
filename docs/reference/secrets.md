# Secrets

Secret metadata and values stored in a configured provider backend (file, Vault, etc.). The API stores metadata; values live only in the provider. Providers are the named backends that secrets are stored in.

## Secret fields

| Field | Type | Notes |
|---|---|---|
| `key` | string | Path-like identifier (e.g. `github/token`) |
| `provider` | string | Provider name |
| `namespace` | string | Namespace within the provider |

Values are write-only on create and readable via GET (returned as plain text).

## Secret API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/secrets` | List secret metadata, filter by `provider`, `namespace` |
| `POST` | `/api/v0/secrets` | Create secret (key + provider + namespace + value) |
| `GET` | `/api/v0/secrets/{key}` | Get secret value (plain text) |
| `DELETE` | `/api/v0/secrets/{key}` | Delete secret |

## Secret CLI

| Command | Description |
|---|---|
| `al secrets list` | List secret metadata |
| `al secrets list --provider <name> --namespace <ns>` | Filter |
| `al secrets create --key <key> --provider <p> --namespace <ns> --value <v>` | Create |
| `al secrets get --key <key> --provider <p> --namespace <ns>` | Get value |
| `al secrets delete --key <key> --provider <p> --namespace <ns>` | Delete |

---

## Provider fields

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | string | Unique name (alphanumeric, `-`, `_`) |
| `type` | string | Backend type (e.g. `file`) |
| `config` | JSON | Provider-specific config |

## Provider API

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v0/secret-providers` | List all providers |
| `POST` | `/api/v0/secret-providers` | Create a custom provider |
| `GET` | `/api/v0/secret-providers/{name}` | Get by name |
| `DELETE` | `/api/v0/secret-providers/{name}` | Delete (built-ins cannot be deleted) |

## Provider CLI

| Command | Description |
|---|---|
| `al secrets provider list` | List all providers |
| `al secrets provider create --name <name> --type <type> --config <json>` | Create |
| `al secrets provider get --name <name>` | Get by name |
| `al secrets provider delete --name <name>` | Delete |
