# Events (CLI)

The `al events` subcommand surfaces recent domain events from the
platform API's in-memory ring buffer.

For the underlying read API see
[Events and Logs — Read API for recent events](../concepts/events.md#read-api-for-recent-events).
For the event model and `aurelion.events` topology see
[Events and Logs](../concepts/events.md).

## Commands

| Command | Description |
|---|---|
| `al events tail` | Tail recent envelopes (newest first). Outputs a JSON array to stdout. |

## `al events tail`

| Option | Default | Notes |
|---|---|---|
| `--limit <n>` | `50` | `1..500`. |
| `--base-url <url>` | env or `http://localhost:8000` | Override the platform API base URL. |

Wraps `GET /api/v0/platform/events?limit=<n>`. The ring buffer is
process-local — values from different platform-API replicas are not
joined. For long-term inspection consume the MQ bus or persist
projections downstream.

A 4xx response is printed to stderr with the response body; the CLI
exits with code `1`.
