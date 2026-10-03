#!/usr/bin/env bats
# Fix J — verify-yq.sh must fail loud if yq is missing.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/verify-yq.sh"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
}

@test "passes when yq is on PATH" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"yq"* ]]
}

@test "fails loud when yq is NOT on PATH" {
  # Minimal PATH that excludes yq. /usr/bin is kept so `command` builtin still works.
  run env -i HOME="$HOME" PATH="/usr/bin:/bin" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"yq required"* ]]
}
