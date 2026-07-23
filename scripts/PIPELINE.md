# Sync Pipeline — keeping git, GSD, GitHub, and the phones consistent

Three sources of truth used to drift because they were reconciled by hand:

1. **`.planning/` (GSD)** — ROADMAP / STATE / MILESTONES (owns *executing* work)
2. **GitHub** — Issues + Project #1 board (owns *unscheduled* backlog + status mirror)
3. **The phones** — via `scripts/auto-deploy.sh`

This pipeline automates the hand-offs. Autonomy is **"auto up to merge"**: CI-less,
you still click *Merge* on every PR; everything up to and after the merge is automatic.

---

## L1 — Board auto-populates (GitHub built-in, zero maintenance)

The Project's built-in **"auto-add to project"** workflow is already enabled: any new
issue (incl. phone-captured ones via the GitHub iOS app) lands on the board
automatically. The **"closed → Done"** built-in is intentionally **not** used — the
reconcile script (L4) owns the Done transition instead, so there's a single writer and
no "stuck In Milestone" drift (which is what actually happened to #33/#34/#35).

## L3 — Merge → auto-deploy (launchd poll on the Mac mini)

`scripts/launchd/com.reojacob.myhome.autodeploy.plist` runs `auto-deploy.sh` every
**30 min**. The script self-gates, so this is cheap:

- **You merge a PR** → within ~30 min both phones get the new `main` (no waiting for a
  nightly window).
- **Quiet week** → silent no-ops, plus the free-provisioning re-sign every 3 days
  (the 7-day-expiry beat, unchanged).

`RunAtLoad` also fires one check at boot/load. launchd never overlaps a single job, so
no locking is needed. (Deploys still gate on *your* merge — nothing reaches the phones
until `main` moves.)

**Install / update the agent:**
```sh
UID_N=$(id -u)
PLIST=~/Library/LaunchAgents/com.reojacob.myhome.autodeploy.plist
launchctl bootout gui/$UID_N "$PLIST" 2>/dev/null
cp scripts/launchd/com.reojacob.myhome.autodeploy.plist "$PLIST"
launchctl bootstrap gui/$UID_N "$PLIST"
launchctl print gui/$UID_N/com.reojacob.myhome.autodeploy | grep -i "run interval"
```
**Revert to the old nightly 21:00 cadence:** restore
`~/Library/LaunchAgents/com.reojacob.myhome.autodeploy.plist.bak` and reload.

> Caveat: if `main` advances while the Xcode Apple ID is signed out, each poll that has
> pending content will fail (and notify) until you re-add the account. That's by design —
> you *want* to know a merge didn't reach the phones — but it's why the account-signed-in
> prerequisite still matters (see the auto-deploy header + memory).

## L4 — Board ↔ reality reconcile (`scripts/sync-tracker.sh`)

The single reliable board writer. Run it **at phase boundaries** (matches the
"update the board at boundaries, not continuously" preference); idempotent, uses the
local `gh` auth (no PAT):

```sh
DRY_RUN=1 ./scripts/sync-tracker.sh            # preview
./scripts/sync-tracker.sh                       # reconcile
IN_PROGRESS="31,43" ./scripts/sync-tracker.sh   # also force these → In Progress
```

What it does:
- **Backfill** — any open issue not on the board → added as `Triaged`.
- **In Progress** — issues with an open linked PR (body/title says `#N`), plus any in
  `$IN_PROGRESS`, → `In Progress`.
- **Done** — issues **closed as COMPLETED** whose card isn't Done → `Done`.
- **Flag** — issues **closed as NOT_PLANNED** (won't-do) are *reported*, never auto-moved
  (the board has no "cancelled" column — decide by hand, e.g. #36).
- **Report** — prints `.planning/STATE.md` active phase/status for a drift eyeball; it
  never edits planning docs (GSD stays the source of truth).

---

## The normal loop, end to end

1. Work a phase on a `feat/…` branch; open a PR with `Closes #N`.
2. `./scripts/sync-tracker.sh` → the issue card flips to **In Progress**.
3. **You merge** the PR (the only manual gate).
4. GitHub closes #N; the L3 poll deploys `main` to both phones within ~30 min.
5. At the phase boundary, `./scripts/sync-tracker.sh` flips the card to **Done** and
   surfaces any drift.

## What is still manual (by design)

- Clicking **Merge** on each PR.
- Re-adding the Xcode Apple ID when its token expires (see auto-deploy notes).
- Deciding what to do with NOT_PLANNED closed issues the reconcile flags.
- Updating `.planning/` docs at milestone/phase boundaries (GSD owns these).
