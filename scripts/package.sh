#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${AIRSTATS_SIGN_IDENTITY:?Set AIRSTATS_SIGN_IDENTITY to a Developer ID Application identity}"
if [[ "$AIRSTATS_SIGN_IDENTITY" == "-" ]]; then
    echo 'Distribution requires a Developer ID identity, not ad-hoc signing.' >&2
    exit 1
fi
if [[ -z "${AIRSTATS_NOTARY_PROFILE:-}" && "${AIRSTATS_ALLOW_UNNOTARIZED:-0}" != "1" ]]; then
    echo 'Set AIRSTATS_NOTARY_PROFILE, or explicitly opt into an unnotarized preview with AIRSTATS_ALLOW_UNNOTARIZED=1.' >&2
    exit 1
fi

# Keep staging directories for inspection; never remove a user-supplied path.
mkdir -p "$PWD/dist/releases"
stage_dir="$(mktemp -d "$PWD/dist/releases/stage.XXXXXX")"
export AIRSTATS_OUTPUT_DIR="$stage_dir/build"
export AIRSTATS_UNIVERSAL=1
bash scripts/build.sh
app_path="$AIRSTATS_OUTPUT_DIR/Air Stats.app"

if [[ -n "${AIRSTATS_NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --keepParent "$app_path" "$stage_dir/AirStats.zip"
    xcrun notarytool submit "$stage_dir/AirStats.zip" --keychain-profile "$AIRSTATS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
    spctl --assess --type execute --verbose=2 "$app_path"
fi

mkdir -p "$stage_dir/volume"
ditto "$app_path" "$stage_dir/volume/Air Stats.app"
ln -s /Applications "$stage_dir/volume/Applications"
cp Resources/Install.txt "$stage_dir/volume/Read Me.txt"
hdiutil create -volname 'Air Stats' -srcfolder "$stage_dir/volume" -ov -format UDZO "$stage_dir/AirStats.dmg"
codesign --force --sign "$AIRSTATS_SIGN_IDENTITY" --timestamp "$stage_dir/AirStats.dmg"
codesign --verify --strict "$stage_dir/AirStats.dmg"
if [[ -n "${AIRSTATS_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$stage_dir/AirStats.dmg" --keychain-profile "$AIRSTATS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$stage_dir/AirStats.dmg"
    xcrun stapler validate "$stage_dir/AirStats.dmg"
else
    echo 'WARNING: Signed preview only. Not notarized; Gatekeeper may block first launch.' >&2
fi
cp "$stage_dir/AirStats.dmg" "$PWD/dist/AirStats.dmg"
(cd dist && shasum -a 256 AirStats.dmg > AirStats.dmg.sha256)
printf 'Release image: %s\nStaging: %s\n' "$PWD/dist/AirStats.dmg" "$stage_dir"
