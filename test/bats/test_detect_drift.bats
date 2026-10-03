#!/usr/bin/env bats
# Task 6/6 (E7N-791) — detect-drift.sh argument validation. Like
# verify-push.sh, the real round-trip (helm package + helm pull against a
# live registry) needs real infrastructure, so this just confirms the
# script fails loud on bad invocation.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/detect-drift.sh"
}

@test "missing chart-dir fails loudly" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"chart-dir required"* ]]
}

@test "missing oci-repo fails loudly" {
  run "$SCRIPT" "poc/version-check-poc-noanchor"
  [ "$status" -ne 0 ]
  [[ "$output" == *"oci-repo required"* ]]
}

@test "nonexistent chart-dir fails loudly" {
  run "$SCRIPT" "poc/does-not-exist" "ghcr.io/org/charts"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
