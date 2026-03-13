# Engineering Studio — Usage

The extension contributes one activity-bar container (**Aurelion**) hosting two tree views, plus a status bar item and a handful of commands.

## Applications view

Lists applications returned by `GET /api/v0/applications`. Each application node expands to show its matching connector instances (`GET /api/v0/applications/{id}/matching-connector-instances`), with their `instance_id`, tag set, and online status.

Item context menu:

- **Focus Application…** — reveals and selects the application node (also reachable from the command palette as `Aurelion: Reveal applications view`).
- **Aurelion: Show logs for application…** — opens a log stream tab (see below).
- **Aurelion: Toggle log streaming for application** — starts or stops polling for a given application without opening a new tab.
- **Aurelion: Refresh this application** — refreshes a single application row.
- On a connector-instance node: **Copy Connector Instance Id** — writes the `instance_id` to the clipboard.

View title actions:

- **Aurelion: Refresh applications** — full reload of the tree.

## Inventory view

A read-only registry of inventory categories. Categories lazy-load on first expand.

Shipped categories:

- **Customers** — lists customers from `GET /api/v0/customers`. Label: `external_id`. Description: `plan_tier`. Tooltip: `customer_id`, `tenant_id`, `mfa_enabled`, `is_locked`, `updated_at`.

Creating, updating, and deleting inventory records is done through the REST API or the CLI — no webview forms or quick-pick mutations are exposed from the Inventory view.

View actions:

- **Aurelion: Refresh inventory** — clears every category's cache.
- **Refresh** (category context menu) — reloads a single category; also reachable via the inline retry action on a failed-to-load placeholder.

## Log streaming

Invoking **Aurelion: Show logs for application…** either from a tree item or the command palette opens a virtual document backed by the `/api/v0/log-buffer` endpoint. The document appends new events on each tick of `logStreamPollMs`. The tab is read-only; close it to stop rendering, or use **Toggle log streaming** to pause without closing.

If the tree refreshes while the quick-pick is open and the selected application is no longer present, the command exits with an informational message rather than opening a stale stream.

## Status bar

A status bar item on the left shows `N / M connectors online` across all applications. Clicking it runs **Aurelion: Reveal applications view**. When the last refresh failed, the item renders in a warning state; the underlying error is in the **Aurelion · Extension** output channel.

## Commands reference

| Command id | Palette title |
|------------|---------------|
| `aurelion.refreshApplications` | Aurelion: Refresh applications |
| `aurelion.openLogs` | Aurelion: Show logs for application… |
| `aurelion.toggleLogStreaming` | Aurelion: Toggle log streaming for application |
| `aurelion.focusApplicationsView` | Aurelion: Reveal applications view |
| `aurelion.refreshInventory` | Aurelion: Refresh inventory |
| `aurelion.focusInventoryView` | Aurelion: Reveal inventory view |

`aurelion.refreshApplication`, `aurelion.refreshInventoryCategory`, `aurelion.copyInstanceId`, and `aurelion.focusApplication` are internal — they are bound to tree context menus and hidden from the command palette.
