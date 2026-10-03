#!/usr/bin/env bash
# Discover which chart directories this run should process, and compute
# each one's OCI repo root. Bash-3.2-safe (sorted temp file, not an
# associative array — see chart-touch-gate.sh for why that matters).
#
# Usage:
#   detect-changed-charts.sh --all
#   detect-changed-charts.sh <base-ref> <head-ref>
#
# Requires OCI_REGISTRY_ROOT env var (e.g. ghcr.io/myorg/charts).
# Prints GITHUB_OUTPUT-compatible lines:
#   matrix=<json: {"include":[{"chart_dir":"...","oci_repo":"..."},...]}>
#   has_charts=true|false

set -euo pipefail

: "${OCI_REGISTRY_ROOT:?OCI_REGISTRY_ROOT env var required (e.g. ghcr.io/myorg/charts)}"

chart_dirs_file="$(mktemp)"
trap 'rm -f "$chart_dirs_file"' EXIT

if [[ "${1:-}" == "--all" ]]; then
  find . -name Chart.yaml -not -path './.git/*' -exec dirname {} \; \
    | sed 's|^\./||' | sort -u > "$chart_dirs_file"
else
  BASE="${1:?base ref required (or pass --all)}"
  HEAD="${2:?head ref required}"

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    dir=$(dirname "$f")
    while [[ "$dir" != "." && "$dir" != "/" ]]; do
      if [[ -f "$dir/Chart.yaml" ]]; then
        echo "$dir" >> "$chart_dirs_file"
        break
      fi
      dir=$(dirname "$dir")
    done
  done < <(git diff --name-only "$BASE".."$HEAD")

  sort -u "$chart_dirs_file" -o "$chart_dirs_file"
fi

if [[ ! -s "$chart_dirs_file" ]]; then
  echo 'matrix={"include":[]}'
  echo "has_charts=false"
  exit 0
fi

entries=""
while IFS= read -r dir; do
  oci_repo="$OCI_REGISTRY_ROOT/$(dirname "$dir")"
  entry="{\"chart_dir\":\"$dir\",\"oci_repo\":\"$oci_repo\"}"
  if [[ -z "$entries" ]]; then
    entries="$entry"
  else
    entries="$entries,$entry"
  fi
done < "$chart_dirs_file"

echo "matrix={\"include\":[$entries]}"
echo "has_charts=true"
