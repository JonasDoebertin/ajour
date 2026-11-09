#!/bin/bash
# Checks the app inside a disk image the way an installed copy will be checked: a strict code signature,
# a stapled notarization ticket, and Gatekeeper's acceptance as notarized.
# Usage: scripts/verify-dmg-app.sh <path to Ajour.dmg>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <image.dmg>" >&2
  exit 2
fi

mount_point="$(mktemp -d)"
trap 'hdiutil detach "$mount_point" -force > /dev/null 2>&1 || true; rmdir "$mount_point" 2> /dev/null || true' EXIT
hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$1" > /dev/null
app="$mount_point/Ajour.app"

codesign --verify --deep --strict --verbose=2 "$app"
xcrun stapler validate "$app"
assessment="$(spctl --assess --type execute --verbose=4 "$app" 2>&1)" || true
echo "$assessment"
if ! grep -q "source=Notarized Developer ID" <<< "$assessment"; then
  echo "Gatekeeper does not accept the app in the disk image as notarized." >&2
  exit 1
fi
