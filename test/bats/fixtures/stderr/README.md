# stderr fixtures — Experiment 1 status

Each `.txt` file in this dir holds a captured `helm show chart` stderr blob
from a specific failure mode. The Fix A regex MUST match the 404-family
blobs and MUST NOT match the transient blobs.

| Case | Expected Fix A regex behavior | Fixture file | Status |
|---|---|---|---|
| 1. Chart exists at version (success) | n/a — no stderr | — | n/a |
| 2. Chart repo exists, version does NOT | REGEX MATCHES | `stderr-404-version.txt` | REAL, re-captured against live GHCR with CI-pinned **helm v3.14.0** (2026-11-18) |
| 3. Chart repo does NOT exist | REGEX MATCHES | `stderr-404-repo.txt` | REAL, re-captured against live GHCR with CI-pinned **helm v3.14.0** (2026-11-18) |
| 4. Auth failure (logged out) | REGEX DOES NOT MATCH | `stderr-auth-failed.txt` | placeholder — see note below |
| 5. Network failure (DNS blackhole) | REGEX DOES NOT MATCH | `stderr-dns-blackhole.txt` | REAL (captured via invalid hostname, 2026-10-03) — **not yet re-verified against helm v3.14.0 specifically**, see note below |
| 6. Registry 5xx / rate limit | REGEX DOES NOT MATCH | `stderr-registry-5xx.txt` | REAL (captured via local fake-503 HTTP server, 2026-10-03) — **not yet re-verified against helm v3.14.0 specifically**, see note below |

**Helm-version provenance note (2026-11-18):** cases 2 and 3 were
re-captured because the original 2026-10-03 capture used whatever helm
version was on the local machine at the time (unrecorded -- since
superseded locally to v3.19.0), not CI's pinned v3.14.0. The actual
wording differed: the original fixture read `Error: failed to perform
"FetchReference" on source: ...: not found`; helm v3.14.0 produces the
shorter `Error: ...: not found` with no "FetchReference" prefix. The
regex still matched both (it keys on `not found`, not the surrounding
text), so this was not a functional bug -- but the fixture now matches
what CI actually sees. Cases 5 and 6 were captured the same way
(uncontrolled local helm version) and have not yet been individually
re-verified against v3.14.0's exact wording -- worth doing if this
pipeline is ported to an environment pinning a different helm version.

**Case 4 note:** confirmed root cause — `docker-credential-osxkeychain`
stores the GHCR PAT keyed by hostname directly in the macOS keychain, and
Helm's OCI client queries that credential helper DIRECTLY, independent of
both `HELM_REGISTRY_CONFIG` and `DOCKER_CONFIG` env vars (tried both,
separately and together — neither blocked it). Genuinely simulating
"logged out" would mean removing/overwriting the one real working
credential every tool on the machine shares for ghcr.io, with no safe way
to restore it mid-session. Didn't pursue further for that reason.
Placeholder content kept as the best available stand-in. See
reference_ghcr_runbook memory for the full credential-helper writeup.

**REAL REGRESSION FOUND (now fixed):** the original regex's bare `no such`
alternative matched Case 5's real stderr — `"...dial tcp: lookup
<host>: no such host"` — meaning a genuine DNS/network failure would have
been misclassified as a safe-to-publish 404 and silently published anyway.
The placeholder fixture used different wording ("connection refused") that
didn't expose this. Caught the moment real capture replaced the placeholder
and `test_version_bump_check.bats` failed. Fixed by scoping `no such` to a
specific following word.

Current regex (`scripts/version-bump-check.sh`):
```
not found|manifest unknown|no such (repository|image|tag|manifest)|name unknown
```
(the bare `404` alternative was removed 2026-11-18 -- it matched the
literal substring "404" anywhere in stderr, including inside a chart's
own version number, e.g. `1.404.0`, misclassifying a real DNS outage as
a safe-to-publish 404. No real fixture here ever needed it.)

`test/bats/test_version_bump_check.bats` no longer duplicates this regex
as a string (2026-11-18) -- it installs a fake `helm` on PATH and calls
the real script end-to-end against each fixture, so the test can't drift
out of sync with the real logic the way a pasted copy could.
