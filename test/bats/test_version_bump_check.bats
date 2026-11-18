#!/usr/bin/env bats
# Fix A tests — 404-family stderr MUST classify as "safe to publish";
# transient classes MUST classify as "refuse, fail closed".
#
# Rewritten 2026-11-18 (5-agent review finding #10): previously this file
# duplicated the stderr-signature regex as its own string and tested that
# copy directly -- nothing enforced the copy stayed in sync with the real
# regex in version-bump-check.sh, so an edit to the real regex could pass
# CI green while this test silently verified stale logic. Now it installs
# a fake `helm` binary (a shim) on PATH that serves a chosen fixture's
# stderr for `helm show chart` and calls the REAL script end-to-end.
#
# Also fixes a masked bug: the old "does NOT match" tests asserted only
# `[ "$status" -ne 0 ]`, which accepts grep's exit 2 (fixture file
# missing/unreadable) as a pass, same as exit 1 (genuinely no match) --
# a missing fixture would have silently passed as "correctly transient."
# Now asserts the script's exact exit code and `action=` output.

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/stderr"
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/version-bump-check.sh"

  SHIM_DIR="$(mktemp -d)"
  PACKAGED_TGZ="$(mktemp)"
  trap 'rm -rf "$SHIM_DIR" "$PACKAGED_TGZ"' EXIT

  cat > "$SHIM_DIR/helm" <<'SHIM'
#!/usr/bin/env bash
# Fake helm: `helm show chart ...` fails, serving $FAKE_HELM_STDERR_FILE
# as stderr, exit 1. Anything else is an error -- these tests never need
# push/pull because the 404/transient path exits before reaching them.
if [[ "$1" == "show" && "$2" == "chart" ]]; then
  cat "$FAKE_HELM_STDERR_FILE" >&2
  exit 1
fi
echo "unexpected helm invocation in test shim: $*" >&2
exit 99
SHIM
  chmod +x "$SHIM_DIR/helm"
  export PATH="$SHIM_DIR:$PATH"
}

_run_against_fixture() {
  export FAKE_HELM_STDERR_FILE="$FIXTURES/$1"
  run "$SCRIPT" "testchart" "1.2.3" "ghcr.io/fake/repo" "$PACKAGED_TGZ"
}

# ─── 404-family MUST classify as publish (chart genuinely not there yet) ───

@test "404-family: version-not-found -> action=publish, exit 0" {
  _run_against_fixture stderr-404-version.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=publish"* ]]
}

@test "404-family: repo-not-found -> action=publish, exit 0" {
  _run_against_fixture stderr-404-repo.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=publish"* ]]
}

# ─── Transient MUST classify as fail (refuse to guess) ───

@test "transient: auth-failed -> action=fail, exit 1 (not exit 2 from a grep error)" {
  _run_against_fixture stderr-auth-failed.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"action=fail"* ]]
}

@test "transient: DNS-blackhole -> action=fail, exit 1" {
  _run_against_fixture stderr-dns-blackhole.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"action=fail"* ]]
}

@test "transient: 5xx -> action=fail, exit 1" {
  _run_against_fixture stderr-registry-5xx.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"action=fail"* ]]
}

@test "transient: rate-limit/generic fallback -> action=fail, exit 1" {
  _run_against_fixture stderr-fallback-generic.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"action=fail"* ]]
}

# ─── Regression: version string containing literal "404" must NOT cause
#     a real transient failure to be misclassified as safe-to-publish ───

@test "REGRESSION: DNS failure whose manifest URL embeds version '1.404.0' -> still action=fail" {
  # The bare `404` regex alternative (removed 2026-11-18) matched this
  # substring regardless of surrounding context -- a real DNS outage on a
  # chart versioned e.g. 1.404.0 was misclassified as a safe 404 purely
  # because the version number supplies the digits. Reproduced live
  # against a real nonexistent host with helm v3.14.0 before fixing.
  cat > "$FIXTURES/../stderr-dns-with-404-in-version.tmp.txt" <<'EOF'
Error: failed to do request: Head "https://nonexistent-host.invalid/v2/charts/poc/foo/manifests/1.404.0": dial tcp: lookup nonexistent-host.invalid: no such host
EOF
  export FAKE_HELM_STDERR_FILE="$FIXTURES/../stderr-dns-with-404-in-version.tmp.txt"
  run "$SCRIPT" "testchart" "1.404.0" "ghcr.io/fake/repo" "$PACKAGED_TGZ"
  rm -f "$FIXTURES/../stderr-dns-with-404-in-version.tmp.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"action=fail"* ]]
}

# ─── Guard: classification is case-insensitive ───

@test "classification is case-insensitive (NOT FOUND / Not Found)" {
  tmp="$(mktemp)"
  echo 'ERROR: NOT FOUND' > "$tmp"
  export FAKE_HELM_STDERR_FILE="$tmp"
  run "$SCRIPT" "testchart" "1.2.3" "ghcr.io/fake/repo" "$PACKAGED_TGZ"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=publish"* ]]
}
