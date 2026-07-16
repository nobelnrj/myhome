# MyHome dev tooling

## `auto-deploy.sh` — defeat the 7-day free-provisioning expiry

Free Apple "Personal Team" apps expire ~7 days after signing and refuse to launch
until re-installed. This script rebuilds MyHome and reinstalls it to both household
iPhones on a schedule, using the **same `xcodebuild` + `devicectl` pipeline as a
manual Xcode run** — so the App Group container / SwiftData store is never disturbed
(reinstalling the same bundle ID is an upgrade install; data is preserved).

### One-time prerequisites
1. **Apple ID signed into Xcode** ▸ Settings ▸ Accounts (free Personal Team is fine).
   *This is required — the build fails without it.*
2. Each phone **USB-paired once** with "Connect via network" enabled in Xcode ▸ Devices.
3. **Developer Mode** enabled on each phone.

### Schedule (launchd)
`~/Library/LaunchAgents/com.reojacob.myhome.autodeploy.plist` runs the script
**Wed + Sun at 21:00** (twice weekly → one missed run still leaves margin in the
7-day window).

```bash
# Load / start the schedule
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reojacob.myhome.autodeploy.plist
# Ensure the Mac wakes for the 21:00 runs (optional)
sudo pmset repeat wakeorpoweron WS 20:58:00
# Run once now to test
launchctl kickstart -k gui/$(id -u)/com.reojacob.myhome.autodeploy
# Stop / unload
launchctl bootout gui/$(id -u)/com.reojacob.myhome.autodeploy
```

### Behavior
- Builds with `-allowProvisioningUpdates` (mints a fresh 7-day profile).
- Installs to each phone best-effort (one phone offline doesn't block the other).
- macOS notification on any failure; logs to `scripts/logs/` (gitignored, pruned >30d).

### Known maintenance (free-tier reality — none of this is zero-touch)
- **Apple ID session** in Xcode expires every few weeks → build fails with a notification →
  re-sign in to Xcode ▸ Accounts (2 min), then rerun.
- A phone not home / locked at run time misses that cycle → notification catches it.
- Paying $99/yr for the Apple Developer Program removes the expiry entirely (1-year
  profiles) and this script becomes unnecessary.
