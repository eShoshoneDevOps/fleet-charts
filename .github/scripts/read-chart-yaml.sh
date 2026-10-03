#!/usr/bin/env bash
# Fix D — extract chart name + version from Chart.yaml via yq (anchor-safe).
#
# Usage:  read-chart-yaml.sh <chart-dir>
# Prints:   name=<name>
#           version=<version>
# Exit 1 on missing/invalid file or missing required fields.

set -euo pipefail

CHART_DIR="${1:-}"
if [[ -z "$CHART_DIR" ]]; then
  echo "::error::read-chart-yaml.sh: chart dir argument required" >&2
  exit 1
fi

CHART_FILE="$CHART_DIR/Chart.yaml"
if [[ ! -f "$CHART_FILE" ]]; then
  echo "::error::$CHART_FILE: not found" >&2
  exit 1
fi

NAME="$(yq eval '.name' "$CHART_FILE")"
VERSION="$(yq eval '.version' "$CHART_FILE")"

# yq returns the literal string "null" for missing keys, not empty.
if [[ -z "$NAME" || "$NAME" == "null" ]]; then
  echo "::error::$CHART_FILE: no name field" >&2
  exit 1
fi
if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
  echo "::error::$CHART_FILE: no version field" >&2
  exit 1
fi

echo "name=$NAME"
echo "version=$VERSION"
