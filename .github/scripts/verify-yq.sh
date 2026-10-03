#!/usr/bin/env bash
# Fix J — fail loud if yq isn't on the runner.
set -euo pipefail

if ! command -v yq >/dev/null 2>&1; then
  echo "::error::yq required but not found on runner" >&2
  exit 1
fi
yq --version
