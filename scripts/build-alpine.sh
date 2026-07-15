#!/usr/bin/env sh
# Build fio as a true musl-static binary inside an Alpine container.
# Out-of-tree build into /w/build so host-side state (if any) never
# leaks in.
#
# CI invokes:
#   docker run --rm --platform linux/$ARCH -v "$PWD":/w -w /w \
#     alpine:3.20 sh -c 'apk add --no-cache bash >/dev/null \
#       && bash /w/scripts/build-alpine.sh && bash /w/scripts/smoke.sh'
#
# Alpine's musl + alpine's gcc → fully static fio binary that runs on
# Alpine AND every glibc distro (Ubuntu/Debian/Fedora/Arch). The
# resulting binary's only "linkage" is libc.so.6 ⇒ none — `ldd` reports
# "not a dynamic executable".
#
# We delegate to scripts/build.sh (with FIO_OS_HINT unset so the host-
# Linux branch picks --build-static), after `apk add`-ing the musl-native
# toolchain + static zlib + the auxiliary deps fio's optional probes
# expect.
set -eu

echo "==> apk add: build deps (musl-native toolchain + static zlib)"
apk add --no-cache \
	build-base \
	bash \
	git \
	linux-headers \
	zlib-dev \
	zlib-static \
	perl

# Alpine ships coreutils-style sha256sum but we don't need it here.
# fio's configure auto-detects lex/yacc if present; flex/bison are
# optional (configure falls back to "no arithmetic parser" if absent).

echo "==> delegate to scripts/build.sh (Linux host → --build-static)"
exec "$(dirname "$0")/build.sh"