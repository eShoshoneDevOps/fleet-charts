#!/usr/bin/env bats
# Fix C — verify-push.sh argument validation. The actual round-trip
# (helm pull against a live registry) needs real infrastructure, so it's
# a Layer 3/POC-level test, not unit-testable here — this just confirms
# the script fails loud and clearly on bad invocation, same bar as every
# other script's "fails loud" coverage.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/verify-push.sh"
}

@test "missing name fails loudly" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"name required"* ]]
}

@test "missing version fails loudly" {
  run "$SCRIPT" "mychart"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version required"* ]]
}

@test "missing oci-repo fails loudly" {
  run "$SCRIPT" "mychart" "0.1.0"
  [ "$status" -ne 0 ]
  [[ "$output" == *"oci-repo required"* ]]
}

@test "missing pushed-tgz path fails loudly" {
  run "$SCRIPT" "mychart" "0.1.0" "ghcr.io/org/charts"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tgz that was just pushed"* ]]
}

@test "missing expected-digest fails loudly" {
  run "$SCRIPT" "mychart" "0.1.0" "ghcr.io/org/charts" "/tmp/fake.tgz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected digest"* ]]
}
