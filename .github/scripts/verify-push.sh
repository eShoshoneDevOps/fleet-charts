#!/usr/bin/env bash
# Fix C — post-push digest round-trip verification. Belt-and-suspenders:
# confirms what `helm push` reported as successfully stored is actually
# retrievable with matching digest AND content, catching upload
# corruption/truncation or a concurrent overwrite that a bare "push
# succeeded" exit code would never reveal.
#
# Usage: verify-push.sh <name> <version> <oci-repo> <pushed-tgz> <expected-digest>
# Exit 0 if digest and content round-trip match; exit 1 otherwise.

set -euo pipefail

NAME="${1:?name required}"
VERSION="${2:?version required}"
OCI_REPO="${3:?oci-repo required}"
PUSHED_TGZ="${4:?path to the tgz that was just pushed required}"
EXPECTED_DIGEST="${5:?expected digest (from helm push output) required}"

FULL_OCI="oci://$OCI_REPO/$NAME"

echo "Verifying round-trip: $FULL_OCI --version $VERSION"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/pulled" "$work/pulled-tree" "$work/pushed-tree"

pull_output="$(helm pull "$FULL_OCI" --version "$VERSION" -d "$work/pulled" 2>&1)"
echo "$pull_output"

actual_digest="$(echo "$pull_output" | grep -oE 'sha256:[a-f0-9]+' | head -1)"

if [[ -z "$actual_digest" ]]; then
  echo "::error::could not determine digest from helm pull output"
  exit 1
fi

if [[ "$actual_digest" != "$EXPECTED_DIGEST" ]]; then
  echo "::error::DIGEST MISMATCH after push"
  echo "::error::  Expected (from helm push): $EXPECTED_DIGEST"
  echo "::error::  Actual (from helm pull):   $actual_digest"
  echo "::error::What was pushed and what is now retrievable from the registry do not match -- possible upload corruption or a concurrent overwrite."
  exit 1
fi

pulled_tgz="$(ls "$work/pulled"/*.tgz)"
tar xzf "$pulled_tgz" -C "$work/pulled-tree"
tar xzf "$PUSHED_TGZ" -C "$work/pushed-tree"

if ! diff -rq "$work/pulled-tree" "$work/pushed-tree" >/dev/null; then
  echo "::error::CONTENT MISMATCH after push (digest matched but extracted content differs -- should not be possible, investigate immediately)"
  diff -rq "$work/pulled-tree" "$work/pushed-tree" || true
  exit 1
fi

echo "::notice::PASS -- round-trip verified, digest and content match: $actual_digest"
