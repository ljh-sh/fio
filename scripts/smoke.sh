#!/usr/bin/env sh
# Smoke test for the freshly-built fio. POSIX; runs on Linux, macOS,
# and the Windows runner (via git-bash).
#
# Three checks, in order:
#   1. version banner — proves the binary loads + reports fio-3.41
#   2. null-engine smoke — no disk I/O, works on every host including
#      read-only CI containers; verifies engine registration + main loop
#   3. disk round-trip on POSIX — actually writes & verifies 64 KiB via
#      psync; skipped on Windows because the smoke-shim is informational
#
# We deliberately do NOT run upstream `make check`. That suite relies
# on root-only ops (raw block device tests, huge tmpfile generations)
# and lives in upstream/fio/t/. CI runs the same upstream `t/fio-dedupe`,
# `t/stest`, etc. binaries that `make` produces anyway, so the
# regression risk on the shipping binary is bounded.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

ext_for() { [ -f "$1.exe" ] && printf '%s.exe' "$1" || printf '%s' "$1"; }
FIO="$(ext_for "$BUILD_DIR/fio")"
[ -x "$FIO" ] || { echo "error: $FIO not built (run scripts/build.sh first)" >&2; exit 1; }

# ---- 1. version banner ----
echo "==> version check"
VOUT="$("$FIO" --version 2>&1)"
echo "    $VOUT"
echo "$VOUT" | grep -q 'fio-3.41' \
	|| { echo "FAIL: expected fio-3.41 in version banner" >&2; exit 1; }

# ---- 2. null-engine smoke (no disk I/O; works on every host) ----
echo "==> null-engine smoke (randrw, runtime=1s, --minimal)"
out="$("$FIO" --name=smoke --ioengine=null --rw=randrw \
        --runtime=1 --time_based --size=1M --minimal 2>&1)"
if [ -z "$out" ]; then
	echo "FAIL: --minimal produced empty output" >&2
	exit 1
fi
# --minimal output (terse_version 3) layout per upstream/fio/stat.c:
#   col1: terse_version (3)
#   col2: fio_version
#   col3: jobname
#   col4: groupid
#   col5: error
#   col6..col9 (per direction): io_bytes_KiB, bw_KiB_per_s, iops, runtime_ms
#   ... per-direction latency + percentile buckets
#   ... CPU + IO-depth + us/ms latency percentiles
# We assert: a non-empty line containing 'fio-3.41' AND a runtime (col 9)
# within [900, 1100] ms. That proves the engine registered, the main
# loop ran for the requested wall time, and the parse path works.
data_line="$(echo "$out" | grep -m1 -E '^3;fio-' || true)"
if [ -z "$data_line" ]; then
	echo "FAIL: --minimal output did not start with the expected header" >&2
	echo "    got: $(echo "$out" | head -c 200)" >&2
	exit 1
fi
runtime_ms="$(echo "$data_line" | awk -F';' '{print $9}')"
case "$runtime_ms" in
	""|*[!0-9]*) echo "FAIL: runtime_ms not numeric (got '$runtime_ms')" >&2; exit 1 ;;
esac
if [ "$runtime_ms" -lt 900 ] || [ "$runtime_ms" -gt 1100 ]; then
	echo "FAIL: runtime_ms=$runtime_ms outside expected [900,1100] window" >&2
	exit 1
fi
iops="$(echo "$data_line" | awk -F';' '{print $8}')"
echo "    OK: data line len=$(echo -n "$data_line" | wc -c | tr -d ' ')"
echo "         runtime_ms=$runtime_ms (≈1s as requested)"
echo "         iops=$iops (null engine; just a sanity check, value irrelevant)"

# ---- 3. disk round-trip on POSIX ----
if [ -d /tmp ] && [ -w /tmp ] && [ "$(uname -s 2>/dev/null)" != "_WIN32" ]; then
	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT
	echo "==> disk round-trip (psync write+verify, 64 KiB → $TMP/fio-smoke.bin)"
	"$FIO" --name=disk-smoke \
	       --ioengine=psync --rw=write \
	       --size=64k --bs=4k \
	       --filename="$TMP/fio-smoke.bin" \
	       --do_verify=1 --verify=md5 \
	       --minimal
	echo "    OK: disk round-trip succeeded (md5 verify passed)"
else
	echo "==> disk round-trip SKIPPED (no writable /tmp or Windows host)"
fi

echo "smoke OK"