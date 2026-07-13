#!/usr/bin/env bash
set -euo pipefail

for command_name in az azd; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command '${command_name}' was not found on PATH." >&2
    exit 1
  fi
done

echo "Required commands are available."

for command_name in docker dab; do
  if command -v "${command_name}" >/dev/null 2>&1; then
    echo "Optional command '${command_name}' is available."
  else
    echo "Optional command '${command_name}' is not installed; it is not required for Phase 1."
  fi
done

echo "No packages, credentials, or Azure resources were changed."
