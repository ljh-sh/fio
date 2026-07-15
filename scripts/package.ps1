# PowerShell: package the Windows fio build into a dist archive.
# Mirrors scripts/package.sh for the Windows / MinGW runner.
#
#   $env:TARGET  e.g. x86_64-windows
#   $env:FIO_SRC (default $ROOT\upstream\fio)
#   $env:DIST    (default $ROOT\dist)
#
# Output: dist\fio-$TARGET.zip + .sha256.

$ErrorActionPreference = "Stop"

$ROOT    = (Resolve-Path -Path "$PSScriptRoot\..").Path
$FIO_SRC = if ($env:FIO_SRC) { $env:FIO_SRC } else { Join-Path $ROOT 'upstream\fio' }
$BUILD_DIR = if ($env:BUILD_DIR) { $env:BUILD_DIR } else { Join-Path $ROOT 'build' }
$DIST    = if ($env:DIST)    { $env:DIST }    else { Join-Path $ROOT 'dist' }
$TARGET  = if ($env:TARGET)  { $env:TARGET }  else { Throw "set TARGET, e.g. x86_64-windows" }

$BIN = Join-Path $BUILD_DIR "fio.exe"
if (-not (Test-Path $BIN)) { Throw "error: $BIN not built (run scripts/build.sh first via msys2 bash)" }

$MAN_SRC = Join-Path $FIO_SRC "fio.1"
if (-not (Test-Path $MAN_SRC)) { Throw "error: $MAN_SRC not found" }

$LICENSE_SRC = Join-Path $FIO_SRC "COPYING"
if (-not (Test-Path $LICENSE_SRC)) { Throw "error: $LICENSE_SRC not found" }

$STAGE = Join-Path $DIST "fio-$TARGET"
if (Test-Path $STAGE) { Remove-Item -Recurse -Force $STAGE }
New-Item -ItemType Directory -Force -Path (Join-Path $STAGE "bin")      | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $STAGE "man\man1") | Out-Null

Copy-Item $BIN (Join-Path $STAGE "bin\fio.exe")
Copy-Item $MAN_SRC (Join-Path $STAGE "man\man1\fio.1")
Copy-Item $LICENSE_SRC (Join-Path $STAGE "LICENSE")
$NOTICE = Join-Path $ROOT "NOTICE.md"
if (Test-Path $NOTICE) { Copy-Item $NOTICE (Join-Path $STAGE "NOTICE") }

# README.
$readme = @'
# fio — single-binary release (Windows)

Self-contained archive from https://github.com/ljh-sh/fio (release tag).
The wrapper LICENSE and NOTICE live there; the `fio.exe` binary carries
the upstream GPL-2.0 license from Jens Axboe.

Install (optional, manual):

    Copy bin\fio.exe to a directory on your PATH, e.g. C:\Windows\System32.
    Then:  fio --version
'@
Set-Content -Path (Join-Path $STAGE "README.md") -Value $readme -Encoding UTF8

# Zip archive.
if (-not (Test-Path $DIST)) { New-Item -ItemType Directory -Force -Path $DIST | Out-Null }
$ARCHIVE = Join-Path $DIST "fio-$TARGET.zip"
if (Test-Path $ARCHIVE) { Remove-Item $ARCHIVE }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
	(Join-Path $DIST ("fio-$TARGET")),
	$ARCHIVE
)

# SHA256 — keyed basename for portability.
$hash = (Get-FileHash -Algorithm SHA256 -Path $ARCHIVE).Hash.ToLower()
"$hash  fio-$TARGET.zip" | Set-Content -Path "$ARCHIVE.sha256" -Encoding ASCII

Write-Host "==> $ARCHIVE"
Write-Host "==> $ARCHIVE.sha256"