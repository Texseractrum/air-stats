#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Local builds remain ad-hoc signed. Release packaging opts into both architectures
# and a Developer ID identity without replacing an already-running local build.
build_args=(-c release)
if [[ "${AIRSTATS_UNIVERSAL:-0}" == "1" ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
output_dir="${AIRSTATS_OUTPUT_DIR:-$PWD/dist}"
app_path="$output_dir/Air Stats.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/AirStats" "$app_path/Contents/MacOS/AirStats"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
swift scripts/icon.swift "$output_dir"
cp "$output_dir/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
sign_args=(--force --sign "${AIRSTATS_SIGN_IDENTITY:--}" --identifier dev.sparkles.airstats)
if [[ "${AIRSTATS_SIGN_IDENTITY:--}" != "-" ]]; then
    sign_args+=(--options runtime --timestamp)
fi
codesign "${sign_args[@]}" "$app_path"
codesign --verify --strict "$app_path"
printf 'Built: %s\n' "$app_path"
