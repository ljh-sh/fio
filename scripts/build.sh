#!/usr/bin/env sh
# Build fio as a static, self-contained binary. Linux gnu + macOS + MinGW.
#
# Out-of-tree (BUILD_DIR=./build) so host glibc builds don't fight with
# alpine musl builds over configure state, and the vendored upstream/
# stays clean (no .o, no config-host.*).
#
# fio's custom configure generates a 2-line wrapper Makefile in BUILD_DIR:
#   SRCDIR := ../upstream/fio
#   include $(SRCDIR)/Makefile
# which pulls in the upstream Makefile. The actual compile runs from
# BUILD_DIR, with all .o files alongside the source in upstream/fio/
# (because Makefile's source paths are relative to SRCDIR). The final
# binary `fio` lands in BUILD_DIR.
#
# Used by:
#   - .github/workflows/build-and-test.yml + release.yml on:
#       ubuntu-latest           (host arch = x86_64-linux-gnu; builds into a
#                                Alpine docker for the *musl* target)
#       ubuntu-24.04-arm        (aarch64 host; same pattern)
#       macos-14                (host arch = aarch64-macos; cross to x86_64)
#       windows-latest          (MSYS2/mingw64 x86_64)
#   - Local development on any POSIX host (no alpine needed).
#
# Cross-compile knobs (all optional):
#   FIO_TARGET_ARCH=arm64|aarch64|x86_64|...   (otherwise defaults to uname -m)
#   CROSS_COMPILE=aarch64-linux-musl-          (otherwise auto-detected from arch)
#   FIO_OS_HINT=darwin|windows                 (otherwise auto: linux|host)
#   FIO_EXTRA_CONFIGURE_ARGS=...               (escape hatch)
#
# Why no --prefix override here: the release archive stages `bin/fio`
# from $BUILD_DIR/fio, not from a `make install` tree, so --prefix is
# just cosmetic. We pin /usr/local to match upstream defaults.
#
# fio produces exactly ONE artifact: `fio` (or `fio.exe` on Windows).
# There is no shared library to worry about — engines self-register via
# ELF constructors in `register_ioengine`.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="${FIO_SRC:-$ROOT/upstream/fio}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

[ -f "$SRC/configure" ] \
	|| { echo "error: $SRC/configure not found (vendoring incomplete?)" >&2; exit 1; }
command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1 \
	|| { echo "error: gcc + make required in PATH" >&2; exit 1; }

mkdir -p "$BUILD_DIR"

# Pin the reported version. Without this, FIO-VERSION-GEN falls back to
# DEF_VER (the upstream maintainers' last baked-in default) which can
# disagree with what we vendored. The fio-3.41 release tarball ships a
# `version` file with exactly this content; we mirror it.
echo "fio-3.41" > "$SRC/version"

# Drop previous configure outputs in $SRC (the wrapper Makefile in
# $BUILD_DIR will re-create the ones it needs; the originals in $SRC
# would shadow them).
rm -f "$SRC/config-host.mak" "$SRC/config-host.h" "$SRC/FIO-VERSION-FILE"

# Drop previous out-of-tree build state (clean rebuilds).
rm -f "$BUILD_DIR/Makefile" "$BUILD_DIR/config-host.mak" "$BUILD_DIR/config-host.h" \
      "$BUILD_DIR/config.log" "$BUILD_DIR/FIO-VERSION-FILE" \
      "$BUILD_DIR/fio" "$BUILD_DIR/fio.exe" \
      "$BUILD_DIR"/lib/.[!.]*.[oh] 2>/dev/null || true

HOST_OS="$(uname -s 2>/dev/null || echo unknown)"
HOST_ARCH="$(uname -m 2>/dev/null || echo unknown)"
TARGET_ARCH="${FIO_TARGET_ARCH:-$HOST_ARCH}"
CROSS_COMPILE="${CROSS_COMPILE:-}"

# Normalize arch aliases so Apple Silicon (arm64) and Linux (aarch64)
# compare equal — otherwise a native darwin build would mistakenly take
# the cross-compile branch and try aarch64-linux-gnu-gcc which doesn't
# exist on macOS.
normalize_arch() {
	case "$1" in
		arm64) printf '%s' aarch64 ;;
		x86_64|amd64) printf '%s' x86_64 ;;
		i386|i486|i586|i686) printf '%s' i386 ;;
		*) printf '%s' "$1" ;;
	esac
}
HOST_ARCH="$(normalize_arch "$HOST_ARCH")"
TARGET_ARCH="$(normalize_arch "$TARGET_ARCH")"
case "$TARGET_ARCH" in
	x86_64|aarch64|ppc64le|powerpc64le|riscv64|s390x|loongarch64|mips64|i386) : ;;
	*) echo "warn: unrecognized TARGET_ARCH=$TARGET_ARCH (passing to --cpu= verbatim)" >&2 ;;
esac

# Configure args.
#   --disable-native                prevents -march=native baking host ISA
#   --disable-shm                   drops SysV shm (smaller binary, no
#                                   observable perf hit for typical workloads)
#   --disable-pmem --disable-rdma --disable-rados --disable-rbd
#       --disable-http --disable-xnvme --disable-libblkio --disable-libzbc
#       --disable-isal --disable-isal64 --disable-libnfs --disable-tcmalloc
#                                   force-disable optional engines whose
#                                   static libs are not portable across
#                                   Alpine/musl + macOS + MinGW. Operators
#                                   who need them can build fio themselves.
CONFIGURE_ARGS="--prefix=/usr/local --disable-native --disable-shm"
CONFIGURE_ARGS="$CONFIGURE_ARGS --disable-pmem --disable-rdma --disable-rados"
CONFIGURE_ARGS="$CONFIGURE_ARGS --disable-rbd --disable-http --disable-xnvme"
CONFIGURE_ARGS="$CONFIGURE_ARGS --disable-libblkio --disable-libzbc --disable-isal"
CONFIGURE_ARGS="$CONFIGURE_ARGS --disable-isal64 --disable-libnfs --disable-tcmalloc"

# Cross-compile / OS hint: tweak CFLAGS / LDFLAGS / --cc so the produced
# binary is shaped for the target platform rather than the host.
if [ "$TARGET_ARCH" != "$HOST_ARCH" ] || [ -n "$CROSS_COMPILE" ] || [ -n "${FIO_OS_HINT:-}" ]; then
	[ -n "$CROSS_COMPILE" ] || CROSS_COMPILE="${TARGET_ARCH}-linux-gnu-"
	CONFIGURE_ARGS="$CONFIGURE_ARGS --cpu=$TARGET_ARCH --cc=${CROSS_COMPILE}gcc"
	case "${FIO_OS_HINT:-}" in
	darwin)
		# Apple SDK is shared between arches; clang auto-discovers via xcrun.
		# `clang -arch $arch` propagates to the linker, so we don't need a
		# separate LDFLAGS (and fio's configure has no --extra-ldflags anyway).
		CONFIGURE_ARGS="$CONFIGURE_ARGS --extra-cflags=-arch $TARGET_ARCH"
		;;
	windows)
		# MinGW cross-toolchain (e.g. x86_64-w64-mingw32-gcc from MSYS2).
		# fio's configure CYGWIN/WIN32 branch auto-sets build_static=yes,
		# so the binary links statically without us passing -static.
		# (fio's configure has no --extra-ldflags option.)
		: "${CFLAGS:=-static}"
		export CFLAGS
		;;
	*)
		# Linux cross-compile — let the cross-toolchain default to its
		# sysroot. For musl, install musl-cross toolchain + use
		# CROSS_COMPILE=aarch64-linux-musl- (Alpine docker does this).
		;;
	esac
fi

# Linux host: --build-static sets -ffunction-sections -fdata-sections on
# CFLAGS and -static -Wl,--gc-sections on LDFLAGS. Verified end-state
# by `ldd build/fio` → "not a dynamic executable" on Linux.
# macOS uses system libc++/libSystem, so --build-static isn't requested.
# Windows configures itself with build_static=yes automatically (see
# configure line ~441-475: CYGWIN/WIN32 branch forces static).
if [ "$HOST_OS" = "Linux" ] && [ -z "${FIO_OS_HINT:-}" ]; then
	CONFIGURE_ARGS="$CONFIGURE_ARGS --build-static"
fi

# fio's oslib/linux-blkzoned.c uses FALLOC_FL_ZERO_RANGE without
# #include <linux/falloc.h> — glibc happens to pull it in transitively
# (e.g. via <sys/ioctl.h>), but musl does not. Set CFLAGS in the env so
# fio's configure preserves it (configure line 47 prepends to $CFLAGS).
# (Idempotent on glibc, no-op there.)
if [ "$HOST_OS" = "Linux" ] && [ -z "${FIO_OS_HINT:-}" ]; then
	: "${CFLAGS:=-include linux/falloc.h}"
	export CFLAGS
fi

[ -n "${FIO_EXTRA_CONFIGURE_ARGS:-}" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS $FIO_EXTRA_CONFIGURE_ARGS"

echo "==> configure out-of-tree (build=$BUILD_DIR, srcdir=$SRC)"
echo "    host=$HOST_OS/$HOST_ARCH → target=$TARGET_ARCH"
echo "    args: $CONFIGURE_ARGS"
( cd "$BUILD_DIR" && "$SRC/configure" $CONFIGURE_ARGS )

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.nproc 2>/dev/null || echo 4)"

# After configure, $BUILD_DIR/Makefile is the wrapper (`include $SRC/Makefile`).
# Make sure $SRC has no stale .o / config artifacts left over from a prior
# in-tree build — defensive idempotency.
( cd "$SRC" && find . -maxdepth 3 \( -name 'config-host.*' -o -name '*.o' \) -delete 2>/dev/null || true )

echo "==> make -C $BUILD_DIR -j$JOBS V=1"
( cd "$BUILD_DIR" && make -j"$JOBS" V=1 )

ext_for() { [ -f "$1.exe" ] && printf '%s.exe' "$1" || printf '%s' "$1"; }
BIN="$(ext_for "$BUILD_DIR/fio")"
[ -x "$BIN" ] || { echo "error: $BIN not built (configure/make failed silently?)" >&2; exit 1; }
echo "==> built: $BIN"
echo "    size : $(du -h "$BIN" | awk '{print $1}')"
echo "    type : $(file -b "$BIN" | head -c 120)"

# Restore vendored upstream/fio/ to a clean state. fio's wrapper Makefile
# is `include $SRC/Makefile`, so .o files compile alongside source (the
# Makefile uses relative paths via $(SRCDIR)). Without this cleanup the
# vendored tree picks up 200+ .o files that pollute `git status`.
# Same logic as `make distclean` — we only touch artifacts we created
# (configure outputs + .o + .d + lex/yacc gen'd), not source.
echo "==> cleanup: remove build artifacts from $SRC"
( cd "$SRC" && find . \( \
       -name 'config-host.mak' -o -name 'config-host.h' -o -name 'FIO-VERSION-FILE' -o -name 'version' -o \
       -name '*.o' -o -name '*.d' -o -name 'lex.yy.*' -o -name 'y.tab.*' -o -name '.depend' \
   \) -delete 2>/dev/null || true )