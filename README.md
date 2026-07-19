# fio — self-contained multi-platform static builds

[Vendored](upstream/fio/) [axboe/fio](https://github.com/axboe/fio) (Jens
Axboe's flexible I/O tester) with a native per-OS packaging layer that
produces **statically-linked, self-contained** binaries. No libaio /
zlib / libpthread to install on the target machine — just download,
extract, and run.

This is a **distribution repo** (fio source + build/packaging scripts +
CI). It is independent of any other ljh-sh project. The x-cmd install
module is handled separately.

## Binaries

Built into each release archive under `bin/`:

| binary   | purpose                                                 |
|----------|---------------------------------------------------------|
| `fio`    | the CLI — flexible I/O tester; list jobs, run profiles  |

(`genfio`, `fio-genzipf`, `fio-verify-state`, `fio-dedupe`, `stest` etc.
— upstream's regression helper binaries — are NOT shipped; they live in
`upstream/fio/t/` and are reachable only by running `make` in the source
tree.)

The man page `fio(1)` is shipped under `man/man1/`.

## Install

The fastest cross-platform one-line install uses x-cmd:

```bash
x eget ljh-sh/fio       # ~1.5 MiB, zero deps, multi-arch static build
```

This installs the `fio` binary to `~/.local/bin/fio`. See the `README.md`
inside each release archive for manual install instructions.

If you don't use x-cmd, grab the archive for your platform from the
[Releases page](https://github.com/ljh-sh/fio/releases), `tar xzf` (or
unzip on Windows), and copy `bin/fio` somewhere on your `$PATH`.

## Platform matrix

Every release builds **6 targets** via GitHub Actions on native runners
(where available) and an Alpine 3.20 docker container for musl-static
Linux builds:

| target                 | runner                        | linkage                | archive   |
|------------------------|-------------------------------|------------------------|-----------|
| `x86_64-linux-musl`    | `ubuntu-latest` + Alpine 3.20 | fully static musl      | `.tar.gz` |
| `aarch64-linux-musl`   | `ubuntu-24.04-arm` + Alpine 3.20 | fully static musl  | `.tar.gz` |
| `aarch64-macos`        | `macos-14`                    | static, system libc++  | `.tar.gz` |
| `x86_64-macos`         | `macos-14` (cross from aarch64) | static, system libc++ | `.tar.gz` |
| `x86_64-windows`       | `windows-latest` + MSYS2 + mingw64 | static (no DLLs)  | `.zip`    |
| `aarch64-windows`*     | `windows-11-arm` + MSYS2 + mingw64 | static (no DLLs) | `.zip`    |

\* `aarch64-windows` is the **6th matrix target** but gated with
`continue-on-error: true` until MSYS2 MINGW64 ships
`mingw-w64-aarch64-gcc` (verified empty as of 2026-07-15; same gap
as `ljh-sh/lhasa` and `ljh-sh/gawk`). When MSYS2 adds the package,
drop the `continue-on-error` exemption and the target builds normally.

> **Linux is musl-only.** Each Linux archive is a single fully static
> binary that runs on Alpine, Debian, Ubuntu, RHEL, Fedora, Arch — every
> Linux distro — with zero system-library dependencies. There is
> intentionally no separate glibc/dynamic Linux variant.

## Self-containedness

- **Linux**: `--build-static` → `-static` → `ldd` reports *not a dynamic executable*.
- **macOS**: static (engines are zero-dep; only `/usr/lib/system/*` and
  `/usr/lib/libSystem.B.dylib` are linked).
- **Windows**: `/MT` static CRT via MinGW; `.exe` ships no DLLs.

## Quick check after install

```bash
$ fio --version
fio-3.41

$ fio --ioengine=null --rw=randrw --runtime=1 --time_based --size=1M --minimal
3;fio-3.41;smoke;0;0;17175736;17158577;4289644;1001;...   # → nonzero IOPS, runtime ≈ 1001ms
```

## Build from source (vendoring update)

This repo ships `upstream/fio/` as a `git subtree` copy of
`axboe/fio.git` tag `fio-3.41` (commit `ed675d3`, 2025-03-XX).
To refresh the vendoring:

```sh
git subtree pull --prefix=upstream/fio \
    https://github.com/axboe/fio.git fio-3.41 --squash
```

Then run `bash scripts/build.sh && bash scripts/smoke.sh` to reproduce
the CI locally. For a true musl-static build:

```sh
docker run --rm --platform linux/amd64 -v "$PWD":/w -w /w alpine:3.20 \
    sh -c 'apk add --no-cache bash >/dev/null \
        && bash /w/scripts/build-alpine.sh && bash /w/scripts/smoke.sh'
```

## CI

Two-stage GitHub Actions:

- `build-and-test.yml` — fires on every push to `main` + every PR;
  full 5-target matrix; uploads per-target artifacts for inspection;
  does NOT publish a GitHub Release.
- `release.yml` — fires on tag push (`v*`) + `workflow_dispatch`;
  same 5-target matrix + softprops/action-gh-release@v2 with
  tarballs, zips, per-archive `.sha256`, and a top-level `SHA256SUMS`.

## License

Combined work is **GPL-2.0-only** (upstream is GPL-2.0-only). The
wrapper layer (`scripts/`, `.github/`, `README.md`, `NOTICE.md`,
`SECURITY.md`, `LICENSE`, `docs/`) is MIT. See
[`NOTICE.md`](NOTICE.md) for the exact split.

## Project status

- **v0.1.0** (2026-07-15) — first release; 5-target matrix; based on
  upstream `fio-3.41`. See [`AUDIT-2026-07-15.md`](AUDIT-2026-07-15.md)
  for the source-level audit that landed with this release.

See <https://fio.ljh.sh> for the rendered Pages site.