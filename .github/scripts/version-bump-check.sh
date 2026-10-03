#!/usr/bin/env bash
# Version-bump check — Fix A (stderr-signature fail-safe) + existing content-diff.
#
# Usage:  version-bump-check.sh <name> <version> <oci-repo> <packaged-tgz>
# Prints: action=publish|skip|fail
# Exit 0 on publish or skip; exit 1 on fail (VERSION-BUMP VIOLATION or transient).

set -euo pipefail

NAME="${1:?name required}"
VERSION="${2:?version required}"
OCI_REPO="${3:?oci-repo required}"
PACKAGED_TGZ="${4:?packaged tgz path required}"

FULL_OCI="oci://$OCI_REPO/$NAME"

echo "Checking whether $FULL_OCI --version $VERSION already exists on registry"

# Capture stderr so we can distinguish real 404 from transient failure.
set +e
show_stderr=$(helm show chart "$FULL_OCI" --version "$VERSION" 2>&1 >/dev/null)
show_exit=$?
set -e

if [[ $show_exit -ne 0 ]]; then
  # Non-zero. Was it a real 404 or a transient failure?
  # NOTE: "no such" is scoped to a specific following word (repository/image/
  # tag/manifest), not bare — a bare "no such" also matches DNS failures like
  # "no such host", which would silently misclassify a network outage as a
  # real 404 and publish anyway. Found via Experiment 1's real stderr capture
  # against live GHCR (the placeholder fixture didn't use this exact wording).
  if echo "$show_stderr" | grep -qiE 'not found|manifest unknown|no such (repository|image|tag|manifest)|name unknown|404'; then
    echo "::notice::PASS — $NAME@$VERSION not yet published, safe to publish"
    echo "action=publish"
    exit 0
  fi

  echo "::error::helm show chart failed with a non-404 signature — refusing to publish"
  echo "::error::exit: $show_exit"
  echo "::error::stderr: $show_stderr"
  echo "::error::Fail-safe: cannot distinguish missing artifact from transient failure."
  echo "action=fail"
  exit 1
fi

echo "$NAME@$VERSION already exists — running content comparison"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/existing-pull" "$work/existing-tree" "$work/new-tree"
helm pull "$FULL_OCI" --version "$VERSION" -d "$work/existing-pull"
existing_tgz=$(ls "$work/existing-pull"/*.tgz)
tar xzf "$existing_tgz" -C "$work/existing-tree"
tar xzf "$PACKAGED_TGZ"  -C "$work/new-tree"

if diff -rq "$work/existing-tree" "$work/new-tree" >/dev/null; then
  echo "::notice::PASS — identical content, existing $VERSION unchanged. SKIP push (idempotent no-op)"
  echo "action=skip"
  exit 0
fi

echo "::error::VERSION-BUMP VIOLATION"
echo "::error::  Chart:    $NAME"
echo "::error::  Version:  $VERSION (unchanged)"
echo "::error::  Content:  DIFFERS from currently-published artifact"
echo "::error::Detected file-level differences:"
diff -rq "$work/existing-tree" "$work/new-tree" || true
echo "::error::This would silently overwrite the existing $VERSION with different content"
echo "::error::Fix: bump the version field in the chart's Chart.yaml before merging."
echo "action=fail"
exit 1
