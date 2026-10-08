#!/usr/bin/env bash
# Packages an unsigned device build as an IPA for sideloading with AltStore.
#
#   scripts/package-ipa.sh build/Device/Build/Products/Release-iphoneos/ScreenshotBrain.app build/ScreenshotBrain.ipa
#
# AltStore re-signs the IPA with your own Apple ID. It keeps the entitlements it finds, so the
# app and its extensions are given the one a free Apple ID can have: the shared App Group (the
# widget and the share extension read the app's data through it). iCloud and Sign in with Apple
# need a paid developer account, so they're left out; the test build skips sign-in instead.
set -euo pipefail

app="$1"
out="$2"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Payload"
cp -R "$app" "$work/Payload/"
bundle="$work/Payload/$(basename "$app")"

group=$(/usr/libexec/PlistBuddy -c "Print :SBAppGroupIdentifier" "$bundle/Info.plist")
entitlements="$work/entitlements.plist"
cat > "$entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>$group</string>
    </array>
</dict>
</plist>
PLIST

executable() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$1/Info.plist"
}

# Inside out: libraries, then extensions, then the app.
find "$bundle" -name "*.dylib" -print0 | while IFS= read -r -d '' lib; do ldid -S "$lib"; done
shopt -s nullglob
for framework in "$bundle"/Frameworks/*.framework; do
  ldid -S "$framework/$(executable "$framework")"
done
for extension in "$bundle"/PlugIns/*.appex; do
  ldid -S"$entitlements" "$extension/$(executable "$extension")"
done
ldid -S"$entitlements" "$bundle/$(executable "$bundle")"

mkdir -p "$(dirname "$out")"
(cd "$work" && zip -qry ScreenshotBrain.ipa Payload)
mv "$work/ScreenshotBrain.ipa" "$out"
echo "Wrote $out ($(du -h "$out" | cut -f1)), App Group $group"
