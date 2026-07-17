#!/bin/zsh
#
# auto-deploy.sh — Rebuild MyHome from an explicit git ref and (re)install to the household iPhones.
#
# Purpose: defeat the 7-day free-provisioning expiry by re-signing + reinstalling
# on a schedule (via launchd), using the SAME xcodebuild + devicectl pipeline as a
# manual Xcode run — so the App Group container / SwiftData store is never disturbed.
#
# WHY REFS, NOT THE WORKING TREE:
#   This script used to build $REPO directly, which meant a scheduled 21:00 run would
#   ship whatever happened to be checked out — including a half-finished phase branch
#   or uncommitted edits — to BOTH phones. It now builds a throwaway `git worktree`
#   pinned to an explicit ref, so what you have checked out is irrelevant.
#
# DEVICE ROLES:
#   Bhuvanya's phone is STABLE — it only ever gets $STABLE_REF (origin/main).
#   Nobel's phone is the TEST device — it gets $TEST_REF, which defaults to the
#   stable ref but can be pointed at a phase branch while testing a PR.
#
# USAGE:
#   ./auto-deploy.sh                             # both phones <- origin/main
#   TEST_REF=feat/18-sync-foundation ./auto-deploy.sh   # your phone <- branch, spouse's <- main
#   DRY_RUN=1 ./auto-deploy.sh                   # resolve refs + plan, skip build/install
#
# ⚠️  SCHEMA DOWNGRADE HAZARD: pointing TEST_REF at a branch that migrates the schema
#   (e.g. SchemaV10/V11) migrates that phone's REAL store in place. SwiftData cannot
#   migrate backward — once installed, reverting that phone to an older-schema main
#   will fail to open the store. Before testing a schema branch on device: prove the
#   migration on the simulator first, and pull the App Group container via
#   Xcode ▸ Devices ▸ MyHome ▸ Download Container so you can restore.
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
REPO="$HOME/My Projects/my-home"
SCHEME="MyHome"
WORK_ROOT="/tmp/myhome-autodeploy"
LOG_DIR="$REPO/scripts/logs"

STABLE_REF="${STABLE_REF:-origin/main}"   # never point this at a branch
TEST_REF="${TEST_REF:-$STABLE_REF}"       # safe to point at a phase branch
DRY_RUN="${DRY_RUN:-0}"

# Device UDIDs (from `xcrun devicectl list devices`)
typeset -A DEVICES
DEVICES[Nobel-iPhone17ProMax]="0FCEDAD1-8B19-52BC-950A-B3B58D106A08"
DEVICES[Bhuvanya-iPhone15ProMax]="F4DD4C3E-BE89-5123-99BD-6568A621296B"

# Which ref each device receives
typeset -A DEVICE_REF
DEVICE_REF[Nobel-iPhone17ProMax]="$TEST_REF"
DEVICE_REF[Bhuvanya-iPhone15ProMax]="$STABLE_REF"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/deploy-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1

notify() { osascript -e "display notification \"$2\" with title \"MyHome auto-deploy\" subtitle \"$1\"" 2>/dev/null || true; }

slug() { echo "${1//[^a-zA-Z0-9]/-}"; }

# Always tear down worktrees, even on failure — a stale worktree blocks the next run.
cleanup() {
  local wt
  for wt in "$WORK_ROOT"/wt-*(N/); do
    git -C "$REPO" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
  done
  git -C "$REPO" worktree prune 2>/dev/null || true
}
trap cleanup EXIT

echo "═══ MyHome auto-deploy — $STAMP ═══"
echo "  stable ref : $STABLE_REF  ->  Bhuvanya-iPhone15ProMax"
echo "  test ref   : $TEST_REF  ->  Nobel-iPhone17ProMax"
[[ "$TEST_REF" != "$STABLE_REF" ]] && echo "  ⚠️  TEST DEVICE IS ON A NON-STABLE REF"

# 0. Fetch so origin/* refs are current
echo "▸ Fetching origin…"
if ! git -C "$REPO" fetch --prune origin; then
  echo "✗ FETCH FAILED — no network, or origin unreachable."
  notify "Fetch failed" "Could not reach origin."
  exit 1
fi

# Resolve every ref up front; refuse to deploy anything that doesn't exist.
typeset -A REF_SHA
for name in ${(k)DEVICES}; do
  ref="${DEVICE_REF[$name]}"
  if ! sha="$(git -C "$REPO" rev-parse --verify --quiet "${ref}^{commit}")"; then
    echo "✗ Ref '$ref' does not resolve — refusing to deploy."
    notify "Bad ref" "'$ref' does not resolve."
    exit 1
  fi
  REF_SHA[$ref]="$sha"
  echo "  $ref = ${sha[1,8]}  ($(git -C "$REPO" log -1 --format=%s "$sha"))"
done

if [[ "$DRY_RUN" == "1" ]]; then
  echo "▸ DRY_RUN=1 — plan resolved, skipping build + install."
  exit 0
fi

# 1. Build each distinct ref in its own worktree (mints a fresh 7-day profile via -allowProvisioningUpdates)
mkdir -p "$WORK_ROOT"
typeset -A APP_FOR_REF
for ref in ${(k)REF_SHA}; do
  s="$(slug "$ref")"
  WT="$WORK_ROOT/wt-$s"
  DERIVED="$WORK_ROOT/dd-$s"

  echo "▸ Building $ref (${REF_SHA[$ref][1,8]})…"
  git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
  git -C "$REPO" worktree add --detach "$WT" "${REF_SHA[$ref]}" >/dev/null

  if ! xcodebuild \
        -project "$WT/MyHome.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates \
        build; then
    echo "✗ BUILD FAILED for $ref — likely Xcode Apple ID session expired. Open Xcode ▸ Accounts and re-sign in."
    notify "Build failed ($ref)" "Re-sign in to Xcode ▸ Accounts, then rerun."
    exit 1
  fi

  APP="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
  if [[ ! -d "$APP" ]]; then
    echo "✗ Built app not found at $APP"
    notify "Build artifact missing" "$APP not found."
    exit 1
  fi
  APP_FOR_REF[$ref]="$APP"
  echo "  ✓ built $ref"
done

# 2. Install to each phone (best-effort; one failure doesn't abort the other)
FAILED=()
for name udid in ${(kv)DEVICES}; do
  ref="${DEVICE_REF[$name]}"
  echo "▸ Installing $ref to $name ($udid)…"
  if xcrun devicectl device install app --device "$udid" "${APP_FOR_REF[$ref]}"; then
    echo "  ✓ $name <- $ref"
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
if [[ "$TEST_REF" != "$STABLE_REF" ]]; then
  notify "Success (test ref live)" "Nobel <- $TEST_REF, Bhuvanya <- $STABLE_REF"
else
  notify "Success" "Both phones refreshed ✓"
fi

# Prune logs older than 30 days
find "$LOG_DIR" -name 'deploy-*.log' -mtime +30 -delete 2>/dev/null || true
