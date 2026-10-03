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
  # A genuinely empty, isolated directory as PATH — not a real system dir
  # like /usr/bin, which GitHub's ubuntu-24.04 runner ships yq inside,
  # making that dir unsuitable for simulating "yq missing" (found via
  # Experiment 4, real CI: this test silently vanished instead of passing,
  # because yq was still reachable through the "minimal" PATH). `command`,
  # `echo`, and `exit` are all shell builtins — none need an external
  # binary, so an empty PATH is safe here.
  empty_path_dir="$(mktemp -d)"
  # Resolve bash's own absolute path BEFORE stripping PATH for the child —
  # env execs by absolute path with no further lookup, so this works
  # regardless of what PATH we hand the child afterward.
  bash_bin="$(command -v bash)"
  run env -i HOME="$HOME" PATH="$empty_path_dir" "$bash_bin" "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"yq required"* ]]
}
