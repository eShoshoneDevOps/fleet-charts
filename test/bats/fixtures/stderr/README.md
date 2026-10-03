# stderr fixtures — FILL IN FROM TALOS EXPERIMENT 1

Each `.txt` file in this dir holds a captured `helm show chart` stderr blob
from a specific failure mode. The Fix A regex MUST match the 404-family
blobs and MUST NOT match the transient blobs.

Fill in each file by running the Experiment 1 commands in the POC handoff
(`~/Documents/handoffs/e7n-791-talos-poc-handoff.md` section 7, Experiment 1).

| Case | Expected Fix A regex behavior | Fixture file |
|---|---|---|
| 1. Chart exists at version (success) | n/a — no stderr | — |
| 2. Chart repo exists, version does NOT | REGEX MATCHES | `stderr-404-version.txt` |
| 3. Chart repo does NOT exist | REGEX MATCHES | `stderr-404-repo.txt` |
| 4. Auth failure (logged out) | REGEX DOES NOT MATCH | `stderr-auth-failed.txt` |
| 5. Network failure (DNS blackhole) | REGEX DOES NOT MATCH | `stderr-dns-blackhole.txt` |
| 6. Registry 5xx / rate limit | REGEX DOES NOT MATCH | `stderr-registry-5xx.txt` |

Case 6 is optional — if hard to synthesize on the POC, skip it. The
`stderr-fallback-generic.txt` file is a catchall "something failed but we
can't tell what" blob for completeness.

Current regex candidate (in `scripts/version-bump-check.sh`):
```
not found|manifest unknown|no such|name unknown|404
```
Tune the regex after capture if case 4/5/6 accidentally match. Bats tests
in `test/test_version_bump_check.bats` will fail loudly on a bad regex.

If you prefer to seed the regex-match tests with placeholder content for
now, each file has a plausible stub below. Replace with real captured
output before merging the E7N-791 PR.
