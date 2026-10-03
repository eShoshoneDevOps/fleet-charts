#!/usr/bin/env bats
# Fix B tests — chart-touch-gate.sh must detect template drift without version bump.
# Each test builds an ephemeral git repo in setup() and runs the gate against it.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/chart-touch-gate.sh"
  REPO="$(mktemp -d)"
  trap 'rm -rf "$REPO"' EXIT

  cd "$REPO"
  git init -q -b main
  git config user.email "bats@test.local"
  git config user.name  "bats"

  mkdir -p mychart/templates
  cat > mychart/Chart.yaml <<'YAML'
apiVersion: v2
name: mychart
type: application
version: 0.1.0
YAML
  cat > mychart/templates/configmap.yaml <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: base
YAML
  cat > mychart/values.yaml <<'YAML'
message: "initial"
YAML

  git add -A
  git commit -q -m 'baseline'
  BASE=$(git rev-parse HEAD)
}

_bump_chart_version() {
  local new="$1"
  sed -i.bak -E "s/^version: .*/version: $new/" mychart/Chart.yaml
  rm -f mychart/Chart.yaml.bak
}

@test "no chart changes → gate passes with no-op notice" {
  echo "unrelated" > README.md
  git add -A && git commit -q -m 'docs change'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to gate"* ]]
}

@test "templates/ change WITHOUT Chart.yaml bump → gate fails" {
  echo '  drift: "r1"' >> mychart/templates/configmap.yaml
  git add -A && git commit -q -m 'drift'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version-bump violation"* ]]
}

@test "templates/ change WITH Chart.yaml bump → gate passes" {
  echo '  drift: "r1"' >> mychart/templates/configmap.yaml
  _bump_chart_version "0.1.1"
  git add -A && git commit -q -m 'drift + bump'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all touched charts have bumped"* ]]
}

@test "values.yaml change WITHOUT Chart.yaml bump → gate fails" {
  sed -i.bak -e 's/initial/drifted/' mychart/values.yaml
  rm -f mychart/values.yaml.bak
  git add -A && git commit -q -m 'values drift'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version-bump violation"* ]]
}

@test "chart dir with README-only change → gate passes (README not gated)" {
  echo 'docs update' > mychart/README.md
  git add -A && git commit -q -m 'docs'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
}

@test "REGRESSION — Chart.yaml with anchor, properly bumped, is detected as changed (yq, not awk)" {
  # Convert the fixture to use an anchor, bump via the anchor-aware extractor.
  cat > mychart/Chart.yaml <<'YAML'
apiVersion: v2
name: mychart
type: application
version: &version 0.1.0
appVersion: *version
YAML
  git add -A && git commit -q -m 'convert to anchor'
  BASE=$(git rev-parse HEAD)

  # Now drift AND bump the anchored version to 0.1.1.
  echo '  drift: "anchor"' >> mychart/templates/configmap.yaml
  sed -i.bak -E "s/version: &version 0.1.0/version: \&version 0.1.1/" mychart/Chart.yaml
  rm -f mychart/Chart.yaml.bak
  git add -A && git commit -q -m 'drift + anchor bump'
  HEAD=$(git rev-parse HEAD)

  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -eq 0 ]
}

@test "REGRESSION — anchor-shaped Chart.yaml without bump still fails (version comparison is anchor-safe)" {
  cat > mychart/Chart.yaml <<'YAML'
apiVersion: v2
name: mychart
type: application
version: &version 0.1.0
appVersion: *version
YAML
  git add -A && git commit -q -m 'anchor baseline'
  BASE=$(git rev-parse HEAD)

  # Drift templates, do NOT bump version.
  echo '  drift: "anchor"' >> mychart/templates/configmap.yaml
  git add -A && git commit -q -m 'drift, no bump'
  HEAD=$(git rev-parse HEAD)

  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version-bump violation"* ]]
}

@test "nested chart (templates deep under subdir) is still detected via Chart.yaml walk-up" {
  mkdir -p mychart/templates/alerts/subdir
  echo 'content' > mychart/templates/alerts/subdir/rule.yaml
  git add -A && git commit -q -m 'nested drift'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version-bump violation"* ]]
}

@test "multiple charts in diff range → each gated independently" {
  mkdir -p chart-b/templates
  cat > chart-b/Chart.yaml <<'YAML'
apiVersion: v2
name: chart-b
type: application
version: 0.1.0
YAML
  echo 'content' > chart-b/templates/cm.yaml
  git add -A && git commit -q -m 'add chart-b'
  BASE=$(git rev-parse HEAD)

  # mychart: drift + bump → OK.
  echo '  drift: "a"' >> mychart/templates/configmap.yaml
  _bump_chart_version "0.1.1"
  # chart-b: drift, no bump → BAD.
  echo 'drift' >> chart-b/templates/cm.yaml

  git add -A && git commit -q -m 'two-chart diff'
  HEAD=$(git rev-parse HEAD)
  run "$SCRIPT" "$BASE" "$HEAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"chart-b"* ]]
  [[ "$output" != *"mychart has template"* ]]
}
