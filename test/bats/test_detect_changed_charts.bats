#!/usr/bin/env bats
# detect-changed-charts.sh — dynamic chart discovery for the publish matrix.
# Each test builds an ephemeral git repo in setup(), mirroring
# test_chart_touch_gate.bats's pattern.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/detect-changed-charts.sh"
  export OCI_REGISTRY_ROOT="ghcr.io/testorg/charts"
  REPO="$(mktemp -d)"
  trap 'rm -rf "$REPO"' EXIT

  cd "$REPO"
  git init -q -b main
  git config user.email "bats@test.local"
  git config user.name  "bats"

  mkdir -p network/cluster-dns/templates
  cat > network/cluster-dns/Chart.yaml <<'YAML'
apiVersion: v2
name: cluster-dns
type: application
version: 0.1.0
YAML
  echo 'content' > network/cluster-dns/templates/configmap.yaml

  mkdir -p cloud/aws/hosted-zone/templates
  cat > cloud/aws/hosted-zone/Chart.yaml <<'YAML'
apiVersion: v2
name: hosted-zone
type: application
version: 0.1.0
YAML
  echo 'content' > cloud/aws/hosted-zone/templates/configmap.yaml

  git add -A
  git commit -q -m 'baseline'
  BASE=$(git rev-parse HEAD)
}

@test "requires OCI_REGISTRY_ROOT env var" {
  unset OCI_REGISTRY_ROOT
  run "$SCRIPT" --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"OCI_REGISTRY_ROOT"* ]]
}

@test "--all discovers every chart regardless of diff" {
  run "$SCRIPT" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_charts=true"* ]]
  [[ "$output" == *"network/cluster-dns"* ]]
  [[ "$output" == *"cloud/aws/hosted-zone"* ]]
}

@test "--all computes oci_repo as REGISTRY_ROOT/parent-dir" {
  run "$SCRIPT" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *'"oci_repo":"ghcr.io/testorg/charts/network"'* ]]
  [[ "$output" == *'"oci_repo":"ghcr.io/testorg/charts/cloud/aws"'* ]]
}

@test "diff mode: no chart touched -> has_charts=false, empty matrix" {
  echo "docs" > README.md
  git add -A && git commit -q -m 'docs only'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_charts=false"* ]]
  [[ "$output" == *'"include":[]'* ]]
}

@test "diff mode: one chart touched -> matrix has exactly that chart" {
  echo '  drift: "r1"' >> network/cluster-dns/templates/configmap.yaml
  git add -A && git commit -q -m 'drift cluster-dns'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has_charts=true"* ]]
  [[ "$output" == *"network/cluster-dns"* ]]
  [[ "$output" != *"hosted-zone"* ]]
}

@test "diff mode: two charts touched -> matrix has both, no duplicates" {
  echo '  drift: "a"' >> network/cluster-dns/templates/configmap.yaml
  echo '  drift: "b"' >> cloud/aws/hosted-zone/templates/configmap.yaml
  git add -A && git commit -q -m 'drift both'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"network/cluster-dns"* ]]
  [[ "$output" == *"cloud/aws/hosted-zone"* ]]
  # each dir should appear exactly once in the matrix
  count=$(echo "$output" | grep -o "cluster-dns" | wc -l)
  [ "$count" -eq 1 ]
}

@test "diff mode: multiple files in the SAME chart dedupe to one matrix entry" {
  echo '  drift: "a"' >> network/cluster-dns/templates/configmap.yaml
  echo 'extra: value' >> network/cluster-dns/values.yaml
  git add -A && git commit -q -m 'two files, one chart'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | grep -o "cluster-dns" | wc -l)
  [ "$count" -eq 1 ]
}

@test "diff mode: nested template path still resolves via Chart.yaml walk-up" {
  mkdir -p network/cluster-dns/templates/subdir
  echo 'content' > network/cluster-dns/templates/subdir/rule.yaml
  git add -A && git commit -q -m 'nested file'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"network/cluster-dns"* ]]
}

@test "missing base/head args fails loudly in diff mode" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"base ref required"* ]]
}

@test "output is valid JSON parseable by yq" {
  run "$SCRIPT" --all
  [ "$status" -eq 0 ]
  matrix_line=$(echo "$output" | grep '^matrix=' | sed 's/^matrix=//')
  echo "$matrix_line" > "$REPO/matrix-check.json"
  # yq can print an output-format warning to stderr depending on the
  # filename extension it infers from — redirect it away so it can't
  # pollute a captured value used in a later numeric comparison.
  count=$(yq eval -p=json '.include | length' "$REPO/matrix-check.json" 2>/dev/null)
  [ "$count" -eq 2 ]
}
