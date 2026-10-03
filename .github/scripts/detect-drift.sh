#!/usr/bin/env bash
# Out-of-band drift detection (task 6/6, E7N-791 guardrail list).
#
# Every other guardrail in this repo (D, A, C, branch protection, CODEOWNERS)
# only constrains what happens INSIDE this pipeline. None of them stop
# someone (including us, this session, while setting up test fixtures) from
# running `helm push` by hand from a laptop -- a manual push bypasses every
# CI check we've built. This script closes that gap from the other side: it
# re-derives what SHOULD be published from git, and diffs it against what
# the registry ACTUALLY has, on a schedule, independent of any push event.
#
# Usage: detect-drift.sh <chart-dir> <oci-repo>
# Exit 0: either not yet published (nothing to compare), or published
#         content matches git HEAD exactly.
# Exit 1: registry has this name@version, but its content differs from
#         what git HEAD would produce -- i.e. drift. Someone pushed
#         something that didn't come from a clean CI run of this commit.

set -euo pipefail

CHART_DIR="${1:?chart-dir required}"
OCI_REPO="${2:?oci-repo required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chart_info="$("$SCRIPT_DIR/read-chart-yaml.sh" "$CHART_DIR")"
NAME="$(echo "$chart_info" | grep '^name=' | cut -d= -f2-)"
VERSION="$(echo "$chart_info" | grep '^version=' | cut -d= -f2-)"

FULL_OCI="oci://$OCI_REPO/$NAME"
echo "Checking drift: $FULL_OCI --version $VERSION (vs. git HEAD: $CHART_DIR)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/git-pkg" "$work/pulled" "$work/git-tree" "$work/pulled-tree"

# Rebuild exactly what CI would have packaged from this commit.
helm dependency update "$CHART_DIR" >/dev/null
helm package "$CHART_DIR" -d "$work/git-pkg" >/dev/null
git_tgz="$(ls "$work/git-pkg"/"$NAME"-*.tgz)"

# Pull what's actually live. A 404 here just means "not published yet" --
# that's a normal, non-drift state, not a failure.
set +e
pull_output="$(helm pull "$FULL_OCI" --version "$VERSION" -d "$work/pulled" 2>&1)"
pull_status=$?
set -e

if [[ $pull_status -ne 0 ]]; then
  if echo "$pull_output" | grep -qiE 'not found|404|no such (repository|image|tag|manifest)'; then
    echo "::notice::$NAME@$VERSION not yet published -- nothing to compare, not drift."
    exit 0
  fi
  echo "$pull_output"
  echo "::error::could not pull $NAME@$VERSION to check for drift (not a clean 404 -- treating as inconclusive, failing closed)"
  exit 1
fi

pulled_tgz="$(ls "$work/pulled"/*.tgz)"
tar xzf "$git_tgz" -C "$work/git-tree"
tar xzf "$pulled_tgz" -C "$work/pulled-tree"

if ! diff -rq "$work/git-tree" "$work/pulled-tree" >/dev/null; then
  echo "::error::DRIFT DETECTED: $NAME@$VERSION in $OCI_REPO does not match what git HEAD ($CHART_DIR) would produce."
  echo "::error::This means the published artifact did NOT come from a clean CI run of the current commit -- likely a manual/out-of-band push."
  diff -rq "$work/git-tree" "$work/pulled-tree" || true
  exit 1
fi

echo "::notice::PASS -- $NAME@$VERSION matches git HEAD, no drift."
