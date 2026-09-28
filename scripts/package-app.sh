#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--skip-build" ]]; then
  swift build --disable-sandbox -c release --product monthly-plan
fi
app_dir="build/Monthly Plan.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/monthly-plan "$app_dir/Contents/MacOS/monthly-plan"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp LICENSE "$app_dir/Contents/Resources/LICENSE"
cp PRIVACY.md TERMS.md "$app_dir/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
