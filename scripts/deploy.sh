#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
az bicep build --file "${repo_root}/infra/main.bicep" --stdout >/dev/null

echo "Bicep validation passed."

if [[ "${1:-}" != "--validate-only" ]]; then
  echo "Deployment remains blocked until Phase 2 preflight, what-if, and azure-validate complete. Use the Azure deployment workflow after validation." >&2
  exit 1
fi
