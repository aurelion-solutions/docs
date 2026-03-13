# Engineering Studio — Configuration

All settings live under the `aurelion.engineeringStudio.*` namespace and can be edited in **Settings → Extensions → Aurelion Engineering Studio**, or directly in `settings.json`.

## Settings reference

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `aurelion.engineeringStudio.apiBaseUrl` | string | `http://localhost:8000` | Base URL of the Aurelion Platform API. Should match `VITE_API_BASE_URL` used by the GUI. No trailing slash — a trailing slash is stripped. |
| `aurelion.engineeringStudio.logStreamPollMs` | number | `2500` | Polling interval for the application log stream, in milliseconds. Minimum effective value: `500`. |
| `aurelion.engineeringStudio.refreshIntervalMs` | number | `0` | Auto-refresh interval for the Applications tree, in milliseconds. `0` disables auto-refresh (manual only). Positive values below `5000` are clamped up to `5000`. |

## Behaviour on change

- Changing `apiBaseUrl` recreates the HTTP client, triggers an immediate refresh of the Applications tree, and resets the log-stream cursor so the next tick starts cleanly against the new kernel.
- Changing `logStreamPollMs` restarts the log streamer's tick on the new cadence.
- Changing `refreshIntervalMs` takes effect on the next tick; `0` halts the auto-refresh timer entirely.

## Example `settings.json`

```jsonc
{
  "aurelion.engineeringStudio.apiBaseUrl": "http://kernel.dev.internal:8000",
  "aurelion.engineeringStudio.logStreamPollMs": 1500,
  "aurelion.engineeringStudio.refreshIntervalMs": 15000
}
```

## Troubleshooting

If the Applications view shows the welcome message with **"No applications loaded"** or the Inventory view renders a failed-to-load placeholder, the usual suspects are:

- `apiBaseUrl` points at a kernel that is not running.
- The kernel is running on a different port than expected.
- A corporate proxy or self-signed TLS is intercepting `fetch`.

Open the **Aurelion · Extension** output channel (View → Output → select **Aurelion · Extension**) for the raw error from the failed request.
