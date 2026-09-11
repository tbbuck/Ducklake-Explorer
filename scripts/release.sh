#!/usr/bin/env bash
#
# Build → bundle engine → Developer-ID sign (hardened runtime) → self-test → notarize →
# staple → DMG. Produces a distributable, notarized DuckLake Explorer.dmg whose app runs on
# a clean Mac with no Homebrew/DuckDB installed.
#
# Requirements:
#   - A "Developer ID Application" identity in the login keychain.
#   - A notarytool keychain profile (default name: ducklake-notary), created once with:
#       xcrun notarytool store-credentials "ducklake-notary" \
#         --apple-id <you@example.com> --team-id 26DMCDBX8L
#     (it prompts for the app-specific password — the value in .ducklake-notary).
#
# Env overrides:
#   CODESIGN_IDENTITY  signing identity            (default: "Developer ID Application")
#   NOTARY_PROFILE     notarytool keychain profile (default: ducklake-notary)
#   SKIP_NOTARIZE=1    sign + package only, no notarization (for local pipeline testing)
#
set -euo pipefail

R="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME=DuckLakeExplorer
CONFIG=Release
APP_NAME="DuckLake Explorer"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ducklake-notary}"
ENTITLEMENTS="$R/Config/DuckLakeExplorer.entitlements"
FIXTURE="$R/Fixtures/sample.ducklake"

BUILD_DIR="${BUILD_DIR:-$R/build}"
DDP="$BUILD_DIR/DerivedData"
APP="$DDP/Build/Products/$CONFIG/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME.dmg"
ZIP="$BUILD_DIR/$APP_NAME.zip"

cd "$R"
mkdir -p "$BUILD_DIR"

echo "==> 1/6  Generate + build ($CONFIG)"
xcodegen generate
xcodebuild -project DuckLakeExplorer.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$DDP" -quiet clean build

echo "==> 2/6  Bundle libduckdb + extensions"
"$R/scripts/bundle-duckdb-engine.sh" "$APP"

echo "==> 3/6  Sign inside-out (Developer ID + hardened runtime)"
# Extensions first — each needs its DuckDB footer stripped, signed, then restored.
find "$APP/Contents/Resources/duckdb-extensions" -name '*.duckdb_extension' -print0 |
  while IFS= read -r -d '' ext; do
    "$R/scripts/sign-duckdb-extension.sh" "$ext" "$IDENTITY"
  done
# The bundled dylib is a plain Mach-O — sign it normally.
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/libduckdb.dylib"
# The app last (seals Frameworks + Resources).
codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" "$APP"
# Verify the app and its nested framework code. The extensions sit in Resources with a DuckDB
# footer after their signature, so they're sealed as resources rather than --deep-verified as
# code; the signed app self-test below is what proves they actually load.
codesign --verify --verbose=2 "$APP"
codesign --verify --verbose=2 "$APP/Contents/Frameworks/libduckdb.dylib"

echo "==> 4/6  Self-test the signed app (loads the bundled engine under library validation)"
out="$("$APP/Contents/MacOS/$APP_NAME" --selftest "$FIXTURE")"
echo "    $out"
case "$out" in
  "selftest OK"*) : ;;
  *) echo "release: signed app failed its engine self-test" >&2; exit 1 ;;
esac

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "==> 5/6  Notarize — SKIPPED (SKIP_NOTARIZE=1)"
else
  echo "==> 5/6  Notarize + staple"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

echo "==> 6/6  Package DMG"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo
echo "Done: $DMG"
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  spctl --assess --type execute --verbose=2 "$APP" || true
fi
