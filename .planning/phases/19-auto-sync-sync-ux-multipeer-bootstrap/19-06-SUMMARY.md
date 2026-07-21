# 19-06 — SyncScope: notes-only sync

**Status:** COMPLETE (code) — folded into the Phase 19 two-phone UAT gate
**Commit:** `b364cc5`
**Trigger:** user directive, not a planned plan — "Can expense be not part of this sync flow… It's too costly and very important data"

## What & Why

P2P sync now carries **notes, note blocks, routine completions** only. Expenses,
categories, accounts, assets, net-worth snapshots, SIPs, SIP amount changes and
contributions never cross the wire.

The user's reasoning was twofold: volume (expenses would flood the spouse's phone with
data she has no use for) and sensitivity (financial history should not be duplicated onto
a second device). The second reason is the binding one — it means the requirement is
"never leaves the device", not merely "not stored on the other phone".

## Design

`SyncScope` (`MyHomeApp/Sync/SyncSnapshot.swift`) is the single source of truth.
It is a **value**, not a hardcoded constant:

- `.production` — `[.note, .noteBlock, .routineCompletion]`. The default everywhere in app code.
- `.all` — every kind. TEST-ONLY. Never passed from app code.

Enforced **twice**, deliberately:

1. **Export** — `SnapshotExporter.makeSnapshot(scope:)` never *fetches* an out-of-scope
   kind. Excluded rows are never materialized, never encoded, never transmitted.
2. **Import** — `SnapshotImporter.merge(_:into:scope:)` re-applies `snapshot.scoped(to:)`
   to every incoming snapshot, so a peer on an older or tampered build cannot push
   out-of-scope rows in.

Tombstones are filtered in both directions too: an out-of-scope `DeletionLog` entry
travelling would let one phone delete rows of a kind it is not allowed to see.

**Wire format unchanged.** All `SyncSnapshot.init` array params default to `[]`, so
excluded kinds simply travel empty — no schema bump, no migration, `currentSchemaVersion`
stays 10.

## Why `SyncScope` is a value

Deleting the expense paths would have thrown away real machinery: Expense identity
adoption by `(sourceAccount, gmailMessageID)` — which stops a bank mail parsed on both
phones from duplicating — and Expense↔Category relationship wiring. Engine tests now run
at `.all` so that stays proven; production paths default to `.production`. Widening scope
later is a one-line edit against tested code.

## Collateral fix — BootstrapAdvisor

`isStoreEffectivelyEmpty` is now scope-relative. It previously counted Expenses toward
"non-empty", which under notes-only scope would mean: a fresh phone auto-ingests one bank
mail → store reads non-empty → the notes bootstrap it genuinely needs is never offered.
The never-clobber guarantee is unaffected, since bootstrap can only touch what it copies.

## UI copy (was untrue after the change)

- **Sync screen footer:** "Only notes and reminders are shared — expenses, accounts and
  investments stay on this phone."
- **Bootstrap sheet:** "Your notes and reminders will be copied over. Expenses, accounts
  and investments stay private to each phone and are never sent."

Both re-screenshotted in light and dark.

## Tests — 703 passing (was 697)

New coverage, all added to existing files (the pbxproj has no synchronized groups):

- `productionExportIsNotesOnly` — full store in, notes/blocks/completions out, all eight financial arrays empty.
- `exportedBytesContainNoMoney` — greps the raw exported JSON for every seeded money value and merchant string.
- `importRefusesOutOfScopeRows` — peer exports at `.all`, receiver merges at production scope, only notes land.
- `importRefusesOutOfScopeTombstones` — a hostile `.expense` tombstone cannot delete a local Expense.
- `expensesNeverCrossTheWire` (SyncCoordinatorTests) — over a fully connected auto-sync link, asserts B has no Expense *and* that the literal string never appears in any bytes A handed the transport.

23 pure-engine call sites in `SnapshotImporterTests` / `SnapshotRoundTripTests` /
`DeletionTrackingTests` gained `scope: .all`; `BootstrapAdvisorTests` partitions its
entity matrix into `syncable` / `outOfScope`.

## Deferred

**Combined asset screen** — user's idea: tap two phones together to see combined household
asset value. Recommended for v1.4 as its own phase, built as an **ephemeral aggregate
exchange** (a total figure on demand), NOT by widening `SyncScope` to replicate asset rows.
Widening would quietly undo this plan.

## Next

Rolls into the existing Phase 19 BLOCKING two-phone UAT in `19-05-SUMMARY.md`, whose
steps 1 and 3 were corrected here to expect notes-only.
