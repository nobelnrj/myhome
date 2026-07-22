#!/bin/zsh
#
# xcode-reclaim.sh — Clear regenerable, unused Xcode data to reclaim disk.
#
# Purpose: Xcode accumulates large disposable caches that it recreates on demand.
# The worst offender is XCTestDevices — throwaway simulator clones that
# `xcodebuild test` spawns per test run and NEVER cleans up (165 clones / hundreds
# of GB of APFS-cloned blocks piled up during normal dev). This script clears the
# safe, regenerable ones on a schedule (via launchd) so the disk never fills.
#
# WHAT IT CLEARS (all safe — Xcode recreates as needed):
#   - ~/Library/Developer/XCTestDevices/*     (ephemeral test-runner sim clones)
#   - ~/Library/Developer/Xcode/DerivedData/* (build products + indexes)
#   - `xcrun simctl delete unavailable`        (orphaned/unavailable simulators)
#
# WHAT IT DELIBERATELY DOES NOT TOUCH:
#   - ~/Library/Developer/CoreSimulator/Devices — your REAL simulators and any
#     seeded app state (e.g. a phase-UAT build). Never wiped here.
#   - Anything under the project or git.
#
# CADENCE: launchd fires this WEEKLY (Sun 03:00). It is idempotent and near-instant
# when there is nothing to clear. Run manually any time: `scripts/xcode-reclaim.sh`.
#
set -uo pipefail

LOG_DIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y-%m-%d %H:%M:%S')"

free_before="$(df -h /System/Volumes/Data | awk 'NR==2{print $4}')"

# 1) XCTestDevices — the big one. rm the whole tree, then recreate the empty dir
#    so Xcode's expected path exists.
XCTD="$HOME/Library/Developer/XCTestDevices"
if [ -d "$XCTD" ]; then
  n="$(ls "$XCTD" 2>/dev/null | wc -l | tr -d ' ')"
  rm -rf "$XCTD" && mkdir -p "$XCTD"
  echo "[$STAMP] cleared XCTestDevices ($n clones)"
fi

# 2) DerivedData — build products + module cache + indexes.
DD="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DD" ]; then
  rm -rf "$DD"/* 2>/dev/null
  echo "[$STAMP] cleared DerivedData"
fi

# 3) Unavailable simulators (only runs if xcrun is present).
if command -v xcrun >/dev/null 2>&1; then
  xcrun simctl delete unavailable >/dev/null 2>&1 && echo "[$STAMP] deleted unavailable simulators"
fi

free_after="$(df -h /System/Volumes/Data | awk 'NR==2{print $4}')"
echo "[$STAMP] free space: ${free_before} -> ${free_after}"
