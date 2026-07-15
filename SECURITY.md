# Security

fio is a 20+ year mature C codebase maintained by **Jens Axboe**
(Linux kernel block layer maintainer). The canonical project lives at
<https://github.com/axboe/fio>; that's where fio is developed, audited,
and bug-fixed.

This repository (`ljh-sh/fio`) is **only a static-build distribution**.
We don't maintain fio; we just compile it as fully self-contained static
binaries for every major platform. We follow upstream's release cadence.

## Reporting vulnerabilities

### Upstream (preferred)

**Please report security issues upstream first.** Upstream's preferred
channels (in priority order):

| channel | contact | notes |
|---------|---------|-------|
| Mailing list | `fio@vger.kernel.org` | upstream's primary support channel |
| GitHub issues | <https://github.com/axboe/fio/issues/new> | for non-sensitive bugs |
| Maintainer email | Jens Axboe <axboe@kernel.dk> | for sensitive / coordinated disclosure |

Upstream does not currently publish a GPG-signed `SECURITY.md`; the
mailing list + maintainer email are the canonical disclosure channel.

### This repository (for build/packaging issues only)

For vulnerabilities **in our wrapper layer** (scripts, CI, package
layout, archive layout) — NOT in fio itself — open a private GitHub
Security Advisory:

<https://github.com/ljh-sh/fio/security/advisories/new>

Or if you prefer email, contact the maintainer at
ljh-sh@users.noreply.github.com (GitHub-verified commit signatures are
available under the `ljh-sh` account; no GPG key published).

## Tracked issues

We track the following known issues in our vendored copy (vendored
commit `ed675d3`, tag `fio-3.41`):

| Date | Upstream commit / CVE | Our vendored fix | Notes |
|------|----------------------|-------------------|-------|
| — | — | — | No CVEs patched locally as of v0.1.0 |

If you find a vulnerability in our build/packaging layer (NOT in fio
itself), please open an issue here.

## Build determinism + integrity

Every release archive ships a sibling `*.sha256` file with a single
hash entry. The combined `SHA256SUMS` aggregates per-archive hashes.

For a stronger check, you can:

1. Verify the archive's `.sha256` matches `sha256sum -c FILE.sha256`.
2. Verify `SHA256SUMS` is published as a release asset (signed by GitHub
   Release attestation once we add cosign).
3. (Most authoritative) Reproduce the build locally:
   `git checkout v0.1.0 && bash scripts/build.sh` and compare the
   resulting `build/fio` against your downloaded `bin/fio` via
   `cmp(1)` after `tar xzf`-ing the archive.

## Per-release security audit

See [`AUDIT-2026-07-15.md`](AUDIT-2026-07-15.md) for the source-level
audit that landed with the first tagged release.

## Trust model

We treat the upstream axboe/fio commit as the trusted artifact and
pin the vendored tree to it (`fio-3.41` → `ed675d3`). Our build scripts
do **not** modify the vendored source; the only outputs are configure
artifacts (`config-host.mak`, `config-host.h`, `FIO-VERSION-FILE`)
inside `upstream/fio/`, which are regenerated on every `make distclean`
and have no bearing on the vendored source itself.