#!/usr/bin/env bash
# Fix B — PR-gate: fail if the diff range touches templates/values/_helpers.tpl
# without bumping Chart.yaml 'version:'. yq-based so YAML anchors don't fool it.
#
# Usage:  chart-touch-gate.sh <base-ref> <head-ref>
# Exit 0 if no violations; exit 1 if any chart touched content without bumping version.

set -euo pipefail

BASE="${1:?base ref required}"
HEAD="${2:?head ref required}"

echo "Comparing $BASE..$HEAD"

# Discover chart dirs touched in the range by walking up to the nearest Chart.yaml.
# Plain temp file + sort -u instead of `declare -A` — associative arrays need
# Bash 4+, and macOS ships Bash 3.2 as /bin/bash with no Homebrew override by
# default. This keeps the script portable to a local macOS run, not just the
# Bash-5 ubuntu-24.04 runner.
chart_dirs_file="$(mktemp)"
trap 'rm -f "$chart_dirs_file"' EXIT

# Capture into a variable first, not `< <(...)` process substitution --
# that runs in a subshell, so `git diff`'s own exit code never reaches
# this script's `set -e`. An invalid range (bad BASE/HEAD) used to print
# "fatal: Invalid revision range" to stderr and still exit 0 with
# "nothing to gate" instead of failing loud.
if ! diff_output="$(git diff --name-only "$BASE".."$HEAD")"; then
  echo "::error::git diff $BASE..$HEAD failed -- cannot determine touched charts" >&2
  exit 1
fi

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
done <<< "$diff_output"

sort -u "$chart_dirs_file" -o "$chart_dirs_file"

if [[ ! -s "$chart_dirs_file" ]]; then
  echo "::notice::no chart directories touched, nothing to gate"
  exit 0
fi

fail=0
while IFS= read -r chart_dir; do
  # Did this range touch content that requires a version bump? Watch the
  # WHOLE chart directory (minus Chart.yaml itself and README.md), not a
  # fixed allowlist of paths -- a real incident's drift lived under
  # controllers/**/values.*.yaml, which the old allowlist
  # (templates/, values.yaml, values.schema.json, _helpers.tpl) would
  # have silently passed. This does not yet parse .helmignore, so a
  # chart with doc/CI files inside its own directory that aren't
  # README.md will still be (over-)gated -- a known, documented
  # limitation, safer to over-gate than under-gate.
  touched_content=$(git diff --name-only "$BASE".."$HEAD" -- \
    "$chart_dir" \
    ":(exclude)$chart_dir/Chart.yaml" \
    ":(exclude)$chart_dir/README.md" \
    | grep -v '^$' || true)

  if [[ -z "$touched_content" ]]; then
    continue
  fi

  # yq, not awk — anchor-safe.
  version_before=$(git show "$BASE:$chart_dir/Chart.yaml" 2>/dev/null | yq eval '.version' - || echo "")
  version_after=$(git show  "$HEAD:$chart_dir/Chart.yaml" 2>/dev/null | yq eval '.version' - || echo "")

  if [[ -z "$version_after" || "$version_after" == "null" ]]; then
    echo "::error file=$chart_dir/Chart.yaml::missing version field"
    fail=1
    continue
  fi

  if [[ "$version_before" == "$version_after" ]]; then
    echo "::error file=$chart_dir/Chart.yaml::version-bump violation — $chart_dir has template/values changes but Chart.yaml version ($version_after) was not bumped"
    echo "::error::Touched files in $chart_dir:"
    while IFS= read -r touched_line; do
      printf '  - %s\n' "$touched_line"
    done <<< "$touched_content"
    echo "::error::Bump $chart_dir/Chart.yaml 'version:' or add the 'skip-version-check' label to this PR."
    fail=1
  fi
done < "$chart_dirs_file"

if [[ $fail -ne 0 ]]; then
  exit 1
fi

echo "::notice::all touched charts have bumped their version"
