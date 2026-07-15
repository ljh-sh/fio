# NOTICE

This repository (`ljh-sh/fio`) provides self-contained, statically-linked
builds of **fio** (Jens Axboe's flexible I/O tester) and the
build/packaging layer around it.

## Vendored upstream

`upstream/fio/` is a copy of [axboe/fio](https://github.com/axboe/fio),
vendored via `git subtree` at the `fio-3.41` tag (commit `ed675d3`,
March 2025). `upstream/fio/COPYING` is retained verbatim.

fio is licensed under the **GNU GPL-2.0-only** by Jens Axboe.

### Pinned patches to the vendored source

The vendored tree carries **no local patches** over upstream `fio-3.41`.
Re-vendor (or `git subtree pull`) to refresh.

```sh
git subtree pull --prefix=upstream/fio \
    https://github.com/axboe/fio.git fio-3.41 --squash
```

## Wrapper license (this repo's own files)

`scripts/`, `.github/workflows/`, `README.md`, `NOTICE.md`, `SECURITY.md`,
`.gitattributes`, `.gitignore`, and `LICENSE` (the MIT half) are

    Copyright (c) 2026 Li Junhao
    Licensed under the MIT License — see LICENSE.

## Combined binary distribution

The vendored source is GPL-2.0-only. The resulting binary is a derivative
work of that source, so each release archive carries:

- `bin/fio` (or `bin/fio.exe`) — GPL-2.0-only (upstream's COPYING applies)
- `LICENSE` (MIT, this wrapper) — for the scripts/CI/docs in this repo
- `NOTICE` — this file

The MIT wrapper license covers the *scripts/CI/docs* in this repository.
The GPL-2.0-only upstream license covers the *binary* and the *source*
under `upstream/fio/`.

## Re-linkability

GPL-2.0-only requires that recipients can relink against a modified version
of the program. This is satisfied by shipping the **exact fio source** under
`upstream/fio/` together with the build scripts in `scripts/` (see
`scripts/build.sh` / `scripts/build-alpine.sh`), which reproduce these
binaries deterministically (modulo toolchain version).

## Third-party dependencies (statically linked into the binaries)

By default, the binaries in this repo statically link only:

- **zlib** — zlib License (when libz.a is present at build time)
- **pthread** + **dl** + **rt** + **m** — libc / glibc / musl / BSD libc

All other optional engines (`libaio`, `libpmem`, `librbd`, `libcurl+openssl`,
`libibverbs`, `libiscsi`, `libnbd`, `libnfs`, `xnvme`, `blkio`, `libzbc`,
`libisal`, `libtcmalloc`, `libhdfs`, `CUDA`, `cuFile`, `libgfapi`, `libdfs`,
`DDN IME`) are explicitly **disabled** at configure time for portability —
see `scripts/build.sh` `--disable-pmem --disable-rdma --disable-rados
--disable-rbd --disable-http --disable-xnvme --disable-libblkio
--disable-libzbc --disable-isal --disable-isal64 --disable-libnfs
--disable-tcmalloc` and `configure --disable-shm`. End users who need
those engines should build fio themselves against those libraries.

## CI matrix carve-out

The `ljh-sh/fio` release matrix is **6 targets**:

- `x86_64-linux-musl`, `aarch64-linux-musl`
- `aarch64-macos`, `x86_64-macos`
- `x86_64-windows`, `aarch64-windows`

`aarch64-windows` is in the matrix as the **6th target** but gated with
`continue-on-error: true` — MSYS2 MINGW64 does not currently ship
`mingw-w64-aarch64-gcc` (verified empty as of 2026-07-15; same gap as
`ljh-sh/lhasa` and `ljh-sh/gawk`). When MSYS2 adds the package, drop
the `continue-on-error` exemption and the target builds normally.