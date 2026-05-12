# Engineering Studio — Overview

**Aurelion Engineering Studio** is a VS Code extension that embeds platform
browsing and light-touch operations into the IDE, so engineers working on
connectors, policies, or inventory do not have to swap between the GUI,
the CLI, and their editor.

## What it does

- Browses **applications** registered in the kernel and the **connector instances** whose tags match each application.
- Browses **inventory** (currently: customers) through a lazy-loaded tree.
- Browses **pipeline runs** by status and drills into per-run and per-step detail panels.
- Validates **pipeline YAML** offline against a bundled JSON Schema — autocomplete and structural checks work without a kernel connection.
- Streams **application logs** from `/api/v0/log-buffer` directly into an editor tab.
- Exposes a status bar widget summarizing how many connector instances are online.

Every call goes through the platform REST API (`/api/v0/...`); the
extension stores no state of its own beyond view caches.

## Scope

The extension is intentionally **read-biased**: most views render kernel
data without mutation. A small set of write operations is exposed through
the API client — notably `updateApplication()`, which issues
`PATCH /api/v0/applications/{id}` to edit fields such as `name`, `code`,
`config`, `required_connector_tags`, and `is_active`. See the
[Applications reference](../../reference/applications.md) for the full
field contract.

UI surfaces for application editing are not shipped; the client method
exists so feature work can build on it without re-plumbing HTTP.

## Installing the `.vsix`

The extension is not published to the Marketplace yet. Install it locally
from a packaged `.vsix`:

1. Build the package from the extension repo:

   ```bash
   cd aurelion-engineering-studio
   pnpm install
   pnpm run package        # produces aurelion-engineering-studio-<version>.vsix
   ```

2. In VS Code, open the Extensions view, click the `...` menu, choose **Install from VSIX...**, and pick the generated file. Alternatively from the terminal:

   ```bash
   code --install-extension aurelion-engineering-studio-0.1.0.vsix
   ```

3. Reload the window. A new **Aurelion** icon appears in the activity bar.

## Requirements

- VS Code `1.90.0` or newer.
- A reachable Aurelion kernel. Default expectation is `http://localhost:8000` — override via `aurelion.engineeringStudio.apiBaseUrl`.

## Where to go next

- [Engineering Studio — Configuration](../../reference/engineering-studio-configuration.md) — settings keys and their defaults.
- [Engineering Studio — Commands and Views](../../reference/engineering-studio.md) — activity-bar surfaces and contributed commands.
- [Engineering Studio troubleshooting](../../guides/engineering-studio-troubleshooting.md) — diagnosing failed loads and stale streams.
