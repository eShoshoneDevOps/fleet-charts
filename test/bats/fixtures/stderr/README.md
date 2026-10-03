# stderr fixtures — Experiment 1 status

Each `.txt` file in this dir holds a captured `helm show chart` stderr blob
from a specific failure mode. The Fix A regex MUST match the 404-family
blobs and MUST NOT match the transient blobs.

| Case | Expected Fix A regex behavior | Fixture file | Status |
|---|---|---|---|
| 1. Chart exists at version (success) | n/a — no stderr | — | n/a |
| 2. Chart repo exists, version does NOT | REGEX MATCHES | `stderr-404-version.txt` | REAL (captured against live GHCR, 2026-10-03) |
| 3. Chart repo does NOT exist | REGEX MATCHES | `stderr-404-repo.txt` | REAL (captured against live GHCR, 2026-10-03) |
| 4. Auth failure (logged out) | REGEX DOES NOT MATCH | `stderr-auth-failed.txt` | placeholder — see note below |
| 5. Network failure (DNS blackhole) | REGEX DOES NOT MATCH | `stderr-dns-blackhole.txt` | REAL (captured via invalid hostname, 2026-10-03) |
| 6. Registry 5xx / rate limit | REGEX DOES NOT MATCH | `stderr-registry-5xx.txt` | placeholder, optional per handoff |

**Case 4 note:** attempted real capture via `HELM_REGISTRY_CONFIG` pointed
at an empty scratch config. Didn't work — the pull still succeeded (exit 0),
meaning the OCI client falls back to another credential source (Docker's
own `credsStore: osxkeychain` in `~/.docker/config.json`) that isn't
controlled by that env var. Didn't pursue further since neutralizing that
credential risks disrupting real shared credentials other tools use.
Placeholder content kept as the best available stand-in.

**REAL REGRESSION FOUND (now fixed):** the original regex's bare `no such`
alternative matched Case 5's real stderr — `"...dial tcp: lookup
<host>: no such host"` — meaning a genuine DNS/network failure would have
been misclassified as a safe-to-publish 404 and silently published anyway.
The placeholder fixture used different wording ("connection refused") that
didn't expose this. Caught the moment real capture replaced the placeholder
and `test_version_bump_check.bats` failed. Fixed by scoping `no such` to a
specific following word.

Current regex (in `scripts/version-bump-check.sh`, kept in sync in
`test/test_version_bump_check.bats`):
```
not found|manifest unknown|no such (repository|image|tag|manifest)|name unknown|404
```
