#!/usr/bin/env bats
# Fix A regex tests — 404-family stderr MUST match; transient classes MUST NOT.
#
# These tests exercise ONLY the stderr-signature regex, not the full
# version-bump-check.sh script (which requires a live registry). Regex is
# duplicated here from scripts/version-bump-check.sh — keep in sync.

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/stderr"
  REGEX='not found|manifest unknown|no such|name unknown|404'
}

_matches() {
  grep -qiE "$REGEX" "$FIXTURES/$1"
}

# ─── 404-family MUST match (would correctly conclude "safe to publish") ───

@test "404-family: version-not-found stderr matches" {
  run _matches stderr-404-version.txt
  [ "$status" -eq 0 ]
}

@test "404-family: repo-not-found stderr matches" {
  run _matches stderr-404-repo.txt
  [ "$status" -eq 0 ]
}

# ─── Transient MUST NOT match (would correctly refuse to publish) ───

@test "transient: auth-failed stderr does NOT match 404 regex" {
  run _matches stderr-auth-failed.txt
  [ "$status" -ne 0 ]
}

@test "transient: DNS-blackhole stderr does NOT match 404 regex" {
  run _matches stderr-dns-blackhole.txt
  [ "$status" -ne 0 ]
}

@test "transient: 5xx stderr does NOT match 404 regex" {
  run _matches stderr-registry-5xx.txt
  [ "$status" -ne 0 ]
}

@test "transient: rate-limit stderr does NOT match 404 regex" {
  run _matches stderr-fallback-generic.txt
  [ "$status" -ne 0 ]
}

# ─── Guard: regex must be case-insensitive ───

@test "regex is case-insensitive (NOT FOUND / Not Found match)" {
  run bash -c "echo 'ERROR: NOT FOUND' | grep -qiE '$REGEX'"
  [ "$status" -eq 0 ]
  run bash -c "echo 'Error: Manifest Unknown' | grep -qiE '$REGEX'"
  [ "$status" -eq 0 ]
}
