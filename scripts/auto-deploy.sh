#!/bin/zsh
#
# auto-deploy.sh — Rebuild MyHome and (re)install to both household iPhones.
#
# Purpose: defeat the 7-day free-provisioning expiry by re-signing + reinstalling
# on a schedule (via launchd), using the SAME xcodebuild + devicectl pipeline as a
# manual Xcode run — so the App Group container / SwiftData store is never disturbed.
#
# Prerequisites (one-time):
#   1. Apple ID signed into Xcode ▸ Settings ▸ Accounts (free Personal Team is fine).
#   2. Each phone USB-paired once with "Connect via network" enabled in Xcode ▸ Devices.
#   3. Developer Mode enabled on each phone.
# At run time: phones on the same Wi-Fi as this Mac, Mac awake, phones unlocked-ish.
#
# Reinstalling with the same bundle ID is an UPGRADE install — SwiftData data is preserved.

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
PROJECT="$HOME/My Projects/my-home/MyHome.xcodeproj"
SCHEME="MyHome"
DERIVED="/tmp/myhome-autodeploy"
LOG_DIR="$HOME/My Projects/my-home/scripts/logs"

# Device UDIDs (from `xcrun devicectl list devices`)
typeset -A DEVICES
DEVICES[Nobel-iPhone17ProMax]="0FCEDAD1-8B19-52BC-950A-B3B58D106A08"
DEVICES[Bhuvanya-iPhone15ProMax]="F4DD4C3E-BE89-5123-99BD-6568A621296B"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/deploy-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1

notify() { osascript -e "display notification \"$2\" with title \"MyHome auto-deploy\" subtitle \"$1\"" 2>/dev/null || true; }

echo "═══ MyHome auto-deploy — $STAMP ═══"

# 1. Build (mints a fresh 7-day provisioning profile via -allowProvisioningUpdates)
echo "▸ Building…"
if ! xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination 'generic/platform=iOS' \
      -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates \
      build; then
  echo "✗ BUILD FAILED — likely Xcode Apple ID session expired. Open Xcode ▸ Accounts and re-sign in."
  notify "Build failed" "Re-sign in to Xcode ▸ Accounts, then rerun."
  exit 1
fi

APP="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ Built app not found at $APP"
  notify "Build artifact missing" "$APP not found."
  exit 1
fi

# 2. Install to each phone (best-effort; one failure doesn't abort the other)
FAILED=()
for name udid in ${(kv)DEVICES}; do
  echo "▸ Installing to $name ($udid)…"
  if xcrun devicectl device install app --device "$udid" "$APP"; then
    echo "  ✓ $name"
  else
    echo "  ✗ $name — phone offline/locked or pairing lost"
    FAILED+=("$name")
  fi
done

# 3. Report
if (( ${#FAILED} > 0 )); then
  echo "✗ Install incomplete: ${FAILED[*]}"
  notify "Install incomplete" "Failed: ${FAILED[*]}. Rerun when phones are home & unlocked."
  exit 1
fi

echo "✓ Deployed to all ${#DEVICES} phones. Profiles fresh for 7 days."
notify "Success" "Both phones refreshed ✓"

# Prune logs older than 30 days
find "$LOG_DIR" -name 'deploy-*.log' -mtime +30 -delete 2>/dev/null || true
