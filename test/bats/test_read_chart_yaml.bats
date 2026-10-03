#!/usr/bin/env bats
# Fix D regression tests — Chart.yaml extraction via yq must be anchor-safe.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/read-chart-yaml.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
}

# Stage a fixture Chart.yaml into a chart-dir shape the script expects.
_stage() {
  local fixture="$1"
  local dir="$TMP/chart-$RANDOM"
  mkdir -p "$dir"
  cp "$FIXTURES/$fixture" "$dir/Chart.yaml"
  echo "$dir"
}

@test "plain scalar version extracts correctly" {
  dir=$(_stage Chart.yaml.plain)
  run "$SCRIPT" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name=testchart-plain"* ]]
  [[ "$output" == *"version=0.1.0"* ]]
}

@test "quoted scalar version extracts to unquoted value" {
  dir=$(_stage Chart.yaml.quoted)
  run "$SCRIPT" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version=0.1.0"* ]]
  [[ "$output" != *'"0.1.0"'* ]]
}

@test "REGRESSION — YAML anchor on version resolves to value, not label (platform-alerts bug)" {
  # The exact production incident shape:
  #   version: &version 0.1.0
  # Old awk extractor returned '&version'. yq must return '0.1.0'.
  dir=$(_stage Chart.yaml.anchor)
  run "$SCRIPT" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version=0.1.0"* ]]
  [[ "$output" != *"&version"* ]]
}

@test "REGRESSION — anchor with downstream *reference still resolves to value" {
  dir=$(_stage Chart.yaml.anchor-with-ref)
  run "$SCRIPT" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version=0.1.0"* ]]
}

@test "quoted-value anchor resolves to unquoted value" {
  dir=$(_stage Chart.yaml.quoted-anchor)
  run "$SCRIPT" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version=0.1.0"* ]]
}

@test "trailing comment on version line does not leak into value" {
  dir=$(_stage Chart.yaml.trailing-comment)
  run "$SCRIPT" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version=0.1.0"* ]]
  [[ "$output" != *"renovate"* ]]
}

@test "missing version field fails with explicit error" {
  dir=$(_stage Chart.yaml.missing-version)
  run "$SCRIPT" "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no version field"* ]]
}

@test "missing name field fails with explicit error" {
  dir=$(_stage Chart.yaml.missing-name)
  run "$SCRIPT" "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no name field"* ]]
}

@test "missing Chart.yaml file fails loudly" {
  run "$SCRIPT" "$TMP/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "missing chart-dir argument fails loudly" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"chart dir argument required"* ]]
}
