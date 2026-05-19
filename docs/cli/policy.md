# Policy (CLI)

The `al policy` subcommand drives the Policy Decision Point (PDP) from
the shell.

For the PDP model see
[Policy Decision Point](../concepts/policy-engine.md).

## Commands

| Command | Description |
|---|---|
| `al policy evaluate` | Evaluate a policy decision against a Facts JSON payload. |

## `al policy evaluate`

Wraps `POST /api/v0/policy/evaluate`. The Facts payload is read from a
file or from standard input.

| Option | Default | Notes |
|---|---|---|
| `--file <path>` | — | Path to a Facts JSON file. When omitted, the CLI reads the payload from stdin. |
| `--base-url <url>` | env or `http://localhost:8000` | Override the platform API base URL. |

Examples:

```bash
# From a file:
al policy evaluate --file ./facts.json

# From stdin:
cat ./facts.json | al policy evaluate
```

Output is the PDP's decision envelope, printed as indented JSON.

Error mapping:

| Condition | Exit | Stream |
|---|---|---|
| Empty input | `1` | stderr |
| Malformed JSON | `1` | stderr |
| HTTP 422 (validation) | `1` | stderr, prefixed `Validation error:` |
| Any other 4xx/5xx | `1` | stderr, prefixed `API error:` |
| Connect / timeout error | `1` | stderr |
