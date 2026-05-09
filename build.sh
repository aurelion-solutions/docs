#!/usr/bin/env bash
set -euo pipefail

# Install uv if it's not on PATH (Cloudflare Workers Builds environment is fresh).
if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "uv version: $(uv --version)"

# Resolve dependencies from pyproject.toml + uv.lock and build the static site.
uv sync --frozen
uv run mkdocs build --strict
