#!/bin/sh
# Builds the iPhone/iPad app (Release) signed with a free Personal Team or a
# paid team, and installs it on a connected device. See docs/IOS_DEVICE.md.
#
#   tools/ios_device_install.sh <TEAM_ID> [device name or UDID]
#
# Needs: Xcode signed in to the Apple ID of that team (Xcode > Settings >
# Accounts), the device paired with this Mac (plugged in once, then Wi-Fi
# works), Developer Mode on the device, and xcodegen.
set -eu
TEAM="${1:?usage: $0 <TEAM_ID> [device]}"
DEVICE="${2:-}"
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
DD=build/dd-device
xcodebuild build -project MangaReader.xcodeproj -scheme MangaReaderiOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -quiet
APP="$DD/Build/Products/Release-iphoneos/MangaReader.app"
if [ -z "$DEVICE" ]; then
  # The first paired iPhone or iPad that is available.
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/physical/ && /available/ && /(iPhone|iPad)/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$|^[0-9A-F-]{25,}$/) {print $i; exit}}')
fi
[ -n "$DEVICE" ] || { echo "No available iPhone or iPad. Unlock it, keep it on the same Wi-Fi or plug it in." >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" com.rustedimac.MangaReader || \
  echo "Installed. If it won't open, trust the developer in Settings > General > VPN & Device Management."
