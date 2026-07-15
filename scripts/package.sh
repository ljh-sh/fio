#!/usr/bin/env sh
# Stage the built fio into a self-contained dist archive. Linux + macOS.
#   TARGET    e.g. x86_64-linux-musl | aarch64-linux-musl | aarch64-macos
#   BUILD_DIR (default $ROOT/build)
#   FIO_SRC   (default $ROOT/upstream/fio — for the man page)
#   DIST      (default $ROOT/dist)
#
# Stage layout inside dist/fio-$TARGET/:
#   bin/fio            (the CLI binary, +x)
#   man/man1/fio.1     (the man page, source roff)
#   README.md          (link to ljh-sh/fio + x eget install)
#
# Output: dist/fio-$TARGET.tar.gz + .sha256 (basename-keyed for portability).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FIO_SRC="${FIO_SRC:-$ROOT/upstream/fio}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST="${DIST:-$ROOT/dist}"
TARGET="${TARGET:?set TARGET, e.g. x86_64-linux-musl}"

ext_for() { [ -f "$1.exe" ] && printf '%s.exe' "$1" || printf '%s' "$1"; }
BIN="$(ext_for "$BUILD_DIR/fio")"
[ -x "$BIN" ] || { echo "error: $BIN not built (run scripts/build.sh first)" >&2; exit 1; }

# Man page lives at upstream/fio/fio.1 (groff/troff source, checked in).
MAN_SRC="$FIO_SRC/fio.1"
[ -f "$MAN_SRC" ] || { echo "error: $MAN_SRC not found" >&2; exit 1; }

# Upstream LICENSE (GPL-2.0) MUST ship with the binary per GPL copyleft.
LICENSE_SRC="$FIO_SRC/COPYING"
[ -f "$LICENSE_SRC" ] || { echo "error: $LICENSE_SRC not found" >&2; exit 1; }

STAGE="$DIST/fio-$TARGET"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/man/man1"

cp "$BIN" "$STAGE/bin/fio"
chmod +x "$STAGE/bin/fio"
cp "$MAN_SRC" "$STAGE/man/man1/fio.1"
cp "$LICENSE_SRC" "$STAGE/LICENSE"
# Also bundle the wrapper NOTICE — explains the LICENSE split (MIT wrapper
# + GPL-2.0 upstream). Build-pipeline users need both to redistribute.
[ -f "$ROOT/NOTICE.md" ] && cp "$ROOT/NOTICE.md" "$STAGE/NOTICE"

# A tiny README so the archive is self-explanatory.
cat > "$STAGE/README.md" <<'EOF'
# fio — single-binary release

Self-contained archive from https://github.com/ljh-sh/fio (release tag).
The wrapper LICENSE and NOTICE live there; the `fio` binary carries the
upstream GPL-2.0 license from Jens Axboe — see `upstream/fio/COPYING`
in the source repo or https://github.com/axboe/fio.

Install (optional, manual):

    sudo install -m 0755 bin/fio /usr/local/bin/fio
    sudo install -m 0644 man/man1/fio.1 /usr/local/share/man/man1/

Then:  man fio
EOF

# Tar archive — keyed basename so downstream users can verify from any cwd.
ARCHIVE="$DIST/fio-$TARGET.tar.gz"
( cd "$DIST" && tar czf "$ARCHIVE" "$(basename "$STAGE")" )

# SHA256 — basename-only so `sha256sum -c FILE.sha256` works from any
# cwd. Prefer coreutils sha256sum, then macOS shasum, then OpenSSL.
if   command -v sha256sum >/dev/null 2>&1; then
	HASH_CMD='sha256sum'
elif command -v shasum     >/dev/null 2>&1; then
	HASH_CMD='shasum -a 256'
else
	HASH_CMD='openssl dgst -sha256 -r'
fi
( cd "$DIST" && $HASH_CMD "fio-$TARGET.tar.gz" \
	| awk '{printf "%s  fio-'"$TARGET"'.tar.gz\n", $1}' ) > "$ARCHIVE.sha256"

echo "==> $ARCHIVE"
echo "==> $ARCHIVE.sha256"