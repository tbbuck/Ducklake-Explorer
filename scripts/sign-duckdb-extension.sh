#!/usr/bin/env bash
#
# Developer-ID sign one .duckdb_extension for a notarized bundle.
#
# DuckDB appends a "duckdb_signature" metadata+signature footer AFTER the Mach-O. codesign
# refuses to sign a file with trailing data ("main executable failed strict validation"), but
# DuckDB refuses to load an extension without that footer ("metadata at the end of the file is
# invalid"). So: strip the footer, sign the clean Mach-O with Developer ID + hardened runtime,
# then re-append the original footer. At load time the app sets allow_unsigned_extensions, so
# DuckDB reads its metadata from the (restored) footer and skips its own signature check, while
# macOS/AMFI validates the Developer-ID code signature over the Mach-O.
#
#   Usage: sign-duckdb-extension.sh <path.duckdb_extension> <signing-identity>
#
set -euo pipefail
EXT="${1:?usage: sign-duckdb-extension.sh <ext> <identity>}"
IDENTITY="${2:?signing identity required}"

macho_end=$(otool -l "$EXT" | awk '
  /__LINKEDIT/{seg=1}
  seg && $1=="fileoff"  {fo=$2}
  seg && $1=="filesize" {print fo+$2; exit}')
[ -n "$macho_end" ] || { echo "sign-duckdb-extension: no __LINKEDIT in $EXT" >&2; exit 1; }

footer="$(mktemp)"
trap 'rm -f "$footer" "$EXT.clean"' EXIT
tail -c +"$((macho_end + 1))" "$EXT" > "$footer"          # save DuckDB footer
head -c "$macho_end" "$EXT" > "$EXT.clean"                # clean Mach-O (no trailing data)
mv "$EXT.clean" "$EXT"
chmod u+w "$EXT"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$EXT"
cat "$footer" >> "$EXT"                                   # restore footer for DuckDB's metadata read
