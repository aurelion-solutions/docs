# Engineering Studio — Configuration

Reference for the Engineering Studio VS Code extension settings. All
keys live under the `aurelion.engineeringStudio.*` namespace and can be
edited in **Settings → Extensions → Aurelion Engineering Studio**, or
directly in `settings.json`.

For the commands and views reference, see [Engineering Studio — Commands and Views](engineering-studio.md).
For diagnosing failed loads, see [Engineering Studio troubleshooting](../guides/engineering-studio-troubleshooting.md).

## Settings

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `aurelion.engineeringStudio.apiBaseUrl` | string | `http://localhost:8000` | Base URL of the Aurelion Platform API. No trailing slash — a trailing slash is stripped. |
| `aurelion.engineeringStudio.logStreamPollMs` | number | `2500` | Polling interval for the application log stream, in milliseconds. Minimum effective value: `500`. |
| `aurelion.engineeringStudio.refreshIntervalMs` | number | `0` | Auto-refresh interval for the Applications tree, in milliseconds. `0` disables auto-refresh (manual only). Positive values below `5000` are clamped up to `5000`. |

## Behaviour on change

- `apiBaseUrl` — change recreates the HTTP client, triggers an immediate refresh of the Applications tree, and resets the log-stream cursor.
- `logStreamPollMs` — change restarts the log streamer's tick on the new cadence.
- `refreshIntervalMs` — change takes effect on the next tick; `0` halts the auto-refresh timer entirely.

## Example `settings.json`

```jsonc
{
  "aurelion.engineeringStudio.apiBaseUrl": "http://kernel.dev.internal:8000",
  "aurelion.engineeringStudio.logStreamPollMs": 1500,
  "aurelion.engineeringStudio.refreshIntervalMs": 15000
}
```
