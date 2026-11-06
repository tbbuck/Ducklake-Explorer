#!/usr/bin/env bash
#
# Fetch the pinned official DuckDB release into Vendor/duckdb (gitignored) and verify its
# SHA-256. Package.swift, the CDuckDB module map, project.yml and bundle-duckdb-engine.sh all
# build against that directory. Idempotent: does nothing when the pinned archive is in place.
#
# To upgrade DuckDB, change VERSION and SHA256 (GitHub lists a digest for each release asset):
#   gh release view v<VERSION> --repo duckdb/duckdb --json assets
#
set -euo pipefail

VERSION="2.0.0"
ASSET="duckdb-shared-libs-osx-arm64.tar.gz"
SHA256="c35d60080b31ba5d11a3ce505a6831be784f003b4c575d32a4c2badb3b41cdf0"

R="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$R/Vendor/duckdb"
STAMP="$DEST/.archive-sha256"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$SHA256" ]; then
  echo "DuckDB v$VERSION already in $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading DuckDB v$VERSION ($ASSET)"
curl -fsSL --retry 3 -o "$WORK/$ASSET" \
  "https://github.com/duckdb/duckdb/releases/download/v$VERSION/$ASSET"
echo "$SHA256  $WORK/$ASSET" | shasum -a 256 -c -

mkdir "$WORK/extracted"
tar -xzf "$WORK/$ASSET" -C "$WORK/extracted"

rm -rf "$DEST"
mkdir -p "$DEST"
cp "$WORK/extracted/duckdb.h" "$WORK/extracted/libduckdb.dylib" "$DEST/"
echo "$SHA256" > "$STAMP"
echo "Installed DuckDB v$VERSION into $DEST"
