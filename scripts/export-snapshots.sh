#!/usr/bin/env bash
# Exports every route in scripts/snapshot-routes.txt on iPhone 16 Pro and iPhone SE, in light and dark,
# into design/. Run after `xcodebuild build-for-testing` into $DERIVED_DATA (default build/DerivedData).
#
# Routes named lab.<name> are design-lab exports and go to design/lab/<name>-<appearance>.png
# (iPhone 16 Pro only). Every other route is an app screen and goes to design/screens/<device>/.
set -euo pipefail
cd "$(dirname "$0")/.."
failed=0
shopt -s nullglob

derived_data="${DERIVED_DATA:-build/DerivedData}"
all_routes=$(grep -vE '^[[:space:]]*(#|$)' scripts/snapshot-routes.txt)
screen_routes=$(echo "$all_routes" | grep -v '^lab\.' | paste -sd, -)
all_routes=$(echo "$all_routes" | paste -sd, -)
devices=("iPhone 16 Pro" "iPhone SE (3rd generation)")

for device in "${devices[@]}"; do
  udid=$(scripts/ensure-simulator.sh "$device")
  slug=$(echo "$device" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/-+$//')
  out="$PWD/build/snapshots/$slug"
  rm -rf "$out"
  mkdir -p "$out"

  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100

  # Design-lab pages are only exported once, on the large phone.
  routes="$screen_routes"
  if [[ "$slug" == "iphone-16-pro" ]]; then routes="$all_routes"; fi

  # Keep going if a screen crashes: the others still export, and the run fails at the end.
  if ! TEST_RUNNER_SB_SNAPSHOT_ROUTES="$routes" TEST_RUNNER_SB_SNAPSHOT_DIR="$out" \
    xcodebuild test-without-building -project ScreenshotBrain.xcodeproj -scheme ScreenshotBrain \
      -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$derived_data" \
      -only-testing:ScreenshotBrainUITests/SnapshotExportTests \
      | xcbeautify; then
    failed=1
  fi
  echo "Exported on $device:"
  ls "$out"
  if [[ -f "$out/failures.txt" ]]; then
    echo "::error::Screens that didn't render on $device: $(paste -sd, "$out/failures.txt")"
  fi

  mkdir -p design/lab "design/screens/$slug"
  for file in "$out"/*.png; do
    base=$(basename "$file")
    if [[ "$base" == lab.* ]]; then
      if [[ "$slug" == "iphone-16-pro" ]]; then
        cp "$file" "design/lab/${base#lab.}"
      fi
    else
      cp "$file" "design/screens/$slug/$base"
    fi
  done
done

exit "$failed"
