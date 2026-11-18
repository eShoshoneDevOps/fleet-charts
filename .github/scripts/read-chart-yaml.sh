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

# GITHUB_OUTPUT injection guard: this script's stdout is appended directly
# to $GITHUB_OUTPUT by the caller (`>> "$GITHUB_OUTPUT"`). A multi-line
# YAML scalar for name/version (e.g. a block literal `name: |`) would
# otherwise put extra, attacker-chosen lines straight into that file,
# each becoming its own forged step output. Reproduced live (2026-11-18):
# a Chart.yaml with `name: |\n  evilname\n  extra=injected` emitted a
# literal `extra=injected` output line. name/version must be a single
# line each, full stop.
if [[ "$NAME" == *$'\n'* ]]; then
  echo "::error::$CHART_FILE: 'name' must be a single-line scalar, not multi-line" >&2
  exit 1
fi
if [[ "$VERSION" == *$'\n'* ]]; then
  echo "::error::$CHART_FILE: 'version' must be a single-line scalar, not multi-line" >&2
  exit 1
fi

echo "name=$NAME"
echo "version=$VERSION"
