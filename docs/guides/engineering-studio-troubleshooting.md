# Engineering Studio troubleshooting

How to diagnose a misbehaving Aurelion VS Code extension. For the
configuration reference, see [Engineering Studio — Configuration](../reference/engineering-studio-configuration.md).

## Applications view shows "No applications loaded"

The welcome message indicates the Applications tree is empty or the kernel
call failed. Likely causes:

- `aurelion.engineeringStudio.apiBaseUrl` points at a kernel that is not running.
- The kernel is listening on a different port than expected.
- A corporate proxy or self-signed TLS is intercepting the extension's `fetch`.

To inspect the underlying error:

1. Open the **Aurelion · Extension** output channel: **View → Output → select Aurelion · Extension**.
2. Read the most recent failure entry. The raw status code and message from the failed request appear there.

## Inventory view renders a "failed to load" placeholder

Same root causes as above — categories lazy-load over HTTP and any failure
surfaces as a placeholder with an inline retry action. Click **Refresh**
on the affected category once the underlying issue is fixed; no extension
reload is required.

## Status bar item is in warning state

The status bar item turns yellow when the last applications refresh
failed. The underlying error is in the **Aurelion · Extension** output
channel. Hover the item for the most recent error summary.

## Log stream tab is empty or stale

- If the tab is empty: the kernel returned no log events for the
  selected application within the polling window. Confirm the application
  is producing logs via the kernel REST API directly.
- If the tab seems stale: the streamer may be paused. Use **Aurelion:
  Toggle log streaming for application** to resume polling without
  reopening the tab.

## Commands missing from the palette

Internal-only commands (`aurelion.refreshApplication`,
`aurelion.refreshInventoryCategory`, `aurelion.copyInstanceId`,
`aurelion.focusApplication`) are deliberately hidden — they are bound to
tree context menus, not the command palette. The full command list is in
the [Commands and Views reference](../reference/engineering-studio.md#commands).
