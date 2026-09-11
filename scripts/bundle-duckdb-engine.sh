#!/usr/bin/env bash
#
# Make a built "DuckLake Explorer.app" self-contained: bundle libduckdb and the pinned
# DuckLake extensions, and rewrite install names so the app needs neither Homebrew nor
# ~/.duckdb at runtime. Idempotent — safe to run repeatedly on the same bundle.
#
# It does NOT codesign; signing + notarization live in scripts/release.sh, which runs this
# first and then signs the whole bundle inside-out (the extensions load with
# allow_unsigned_extensions because re-signing invalidates DuckDB's own signature).
#
#   Usage: scripts/bundle-duckdb-engine.sh "/path/to/DuckLake Explorer.app"
#
# Optional overrides (for CI or non-standard installs):
#   DUCKDB_LIB=/abs/libduckdb.dylib   pin the source dylib explicitly
#
set -euo pipefail

APP="${1:?usage: bundle-duckdb-engine.sh <path-to-.app>}"
[ -d "$APP" ] || { echo "error: not an app bundle: $APP" >&2; exit 1; }

# The extensions the app loads at runtime (see LakeSession.loadCoreExtensions).
EXTENSIONS=(ducklake spatial httpfs aws sqlite_scanner)

# --- Resolve engine version, platform, source dylib, extension source dir ----------------
DUCKDB_BIN="$(command -v duckdb || true)"
[ -n "$DUCKDB_BIN" ] || { echo "error: duckdb CLI not found on PATH" >&2; exit 1; }
VERSION="$("$DUCKDB_BIN" --version | awk '{print $1}')"     # e.g. v1.5.5
case "$(uname -m)" in
  arm64)  PLATFORM=osx_arm64 ;;
  x86_64) PLATFORM=osx_amd64 ;;
  *) echo "error: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

SRC_DYLIB="${DUCKDB_LIB:-}"
if [ -z "$SRC_DYLIB" ]; then
  for cand in \
    "$(brew --prefix duckdb 2>/dev/null || true)/lib/libduckdb.dylib" \
    /opt/homebrew/opt/duckdb/lib/libduckdb.dylib \
    /usr/local/opt/duckdb/lib/libduckdb.dylib; do
    [ -f "$cand" ] && { SRC_DYLIB="$cand"; break; }
  done
fi
[ -f "$SRC_DYLIB" ] || { echo "error: libduckdb.dylib not found (set DUCKDB_LIB)" >&2; exit 1; }

EXT_SRC_DIR="$HOME/.duckdb/extensions/$VERSION/$PLATFORM"

# --- Ensure the pinned extensions are present locally (install any missing) ---------------
missing=()
for e in "${EXTENSIONS[@]}"; do
  [ -f "$EXT_SRC_DIR/$e.duckdb_extension" ] || missing+=("$e")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "installing missing extensions for $VERSION/$PLATFORM: ${missing[*]}"
  sql=""
  for e in "${missing[@]}"; do sql+="INSTALL $e; "; done
  "$DUCKDB_BIN" -c "$sql"
fi

# --- Copy into the bundle ----------------------------------------------------------------
FRAMEWORKS="$APP/Contents/Frameworks"
EXT_DST_DIR="$APP/Contents/Resources/duckdb-extensions"
mkdir -p "$FRAMEWORKS" "$EXT_DST_DIR"

DST_DYLIB="$FRAMEWORKS/libduckdb.dylib"
cp -f "$SRC_DYLIB" "$DST_DYLIB"
chmod u+w "$DST_DYLIB"
install_name_tool -id "@rpath/libduckdb.dylib" "$DST_DYLIB"

for e in "${EXTENSIONS[@]}"; do
  cp -f "$EXT_SRC_DIR/$e.duckdb_extension" "$EXT_DST_DIR/$e.duckdb_extension"
  chmod u+w "$EXT_DST_DIR/$e.duckdb_extension"
done

# --- Rewrite the main executable's libduckdb reference + rpath (idempotent) ---------------
EXE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
BIN="$APP/Contents/MacOS/$EXE_NAME"
[ -f "$BIN" ] || { echo "error: executable not found: $BIN" >&2; exit 1; }

current_ref="$(otool -L "$BIN" | awk '/libduckdb\.dylib/ {print $1; exit}')"
if [ -n "$current_ref" ] && [ "$current_ref" != "@rpath/libduckdb.dylib" ]; then
  install_name_tool -change "$current_ref" "@rpath/libduckdb.dylib" "$BIN"
fi
if ! otool -l "$BIN" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN"
fi
# Drop any absolute Homebrew rpath so a dev machine's libduckdb can't shadow the bundled copy.
while read -r stale; do
  [ -n "$stale" ] && install_name_tool -delete_rpath "$stale" "$BIN" || true
done < <(otool -l "$BIN" | awk '/ path / && /duckdb/ {print $2}')

echo "bundled libduckdb $VERSION ($PLATFORM) + ${#EXTENSIONS[@]} extensions into:"
echo "  $APP"
