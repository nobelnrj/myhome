#!/bin/zsh
#
# sync-tracker.sh — reconcile GitHub Project #1 ("My Home") board with reality.
#
# The single, reliable board writer for the "everything in sync" pipeline (L4).
# Uses the local `gh` auth (already has project scope on this Mac), so it needs
# no PAT and no web-UI built-in workflows. Run it at phase boundaries (matches the
# "update the board at boundaries, not continuously" preference) — it is idempotent
# and safe to re-run anytime:
#
#   1. Backfill  — any OPEN issue not on the board is added, defaulted to `Triaged`.
#   2. In Progress — issues with an OPEN linked PR (body/title says "#N"), plus any
#                    numbers passed in $IN_PROGRESS, are moved to `In Progress`.
#   3. Done      — issues that are CLOSED but whose card isn't `Done` are moved to
#                  `Done` (this is what a GitHub built-in workflow WOULD do — we own
#                  it locally instead, so #33-style "stuck In Milestone" can't happen).
#   4. Report    — prints `.planning/STATE.md` active phase/status for a drift eyeball;
#                  never auto-edits planning docs (GSD stays source of truth).
#
# USAGE:
#   ./scripts/sync-tracker.sh                     # reconcile now
#   DRY_RUN=1 ./scripts/sync-tracker.sh           # print the plan, change nothing
#   IN_PROGRESS="31,43" ./scripts/sync-tracker.sh # also force these → In Progress
#
# REQUIRES: `gh` authenticated with project scope (verify: `gh project item-list 1 --owner nobelnrj`).

set -euo pipefail

# ─── Config (IDs from github-project-tracker memory; verified 2026-07-23) ─────
OWNER="nobelnrj"
REPO="nobelnrj/myhome"
PROJECT_NUMBER=1
PROJECT_ID="PVT_kwHOAzLF384BdqIB"
STATUS_FIELD_ID="PVTSSF_lAHOAzLF384BdqIBzhYKIMM"
OPT_TRIAGED="c7168213"
OPT_IN_PROGRESS="6155af6e"
OPT_DONE="d345344a"
# (Inbox=07a6ae95  In Milestone=52de0b18)

DRY_RUN="${DRY_RUN:-0}"
IN_PROGRESS="${IN_PROGRESS:-}"

log() { print -- "$@"; }   # zsh `print` (no -r) interprets \n

log "═══ sync-tracker — Project #$PROJECT_NUMBER ($OWNER) ═══"
[[ "$DRY_RUN" == "1" ]] && log "  (DRY_RUN — no changes will be made)"

# ─── Snapshots ────────────────────────────────────────────────────────────────
open_issues=($(gh issue list --repo "$REPO" --state open --limit 300 --json number -q '.[].number' | sort -n))
# Closed issues split by reason: only COMPLETED closures map to Done. NOT_PLANNED
# ("won't do") closures have no matching board column, so they're flagged, not moved.
completed_set=" $(gh issue list --repo "$REPO" --state closed --limit 500 --json number,stateReason -q '.[]|select(.stateReason=="COMPLETED")|.number' | tr '\n' ' ') "
notplanned_set=" $(gh issue list --repo "$REPO" --state closed --limit 500 --json number,stateReason -q '.[]|select(.stateReason=="NOT_PLANNED")|.number' | tr '\n' ' ') "

# issue number → "itemID<TAB>statusName"  (only rows backed by an issue)
typeset -A item_id item_status
while IFS=$'\t' read -r num iid st; do
  [[ -n "$num" && "$num" != "null" ]] && { item_id[$num]="$iid"; item_status[$num]="$st"; }
done < <(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json --limit 500 \
          | python3 -c "import json,sys
d=json.load(sys.stdin)
for i in d.get('items',[]):
    c=i.get('content',{})
    if c.get('number') is not None:
        print(f\"{c['number']}\t{i['id']}\t{i.get('status','')}\")")

# issue numbers referenced by an OPEN PR (body or title)
typeset -A pr_open
while IFS= read -r n; do [[ -n "$n" ]] && pr_open[$n]=1; done < <(
  gh pr list --repo "$REPO" --state open --limit 100 --json body,title \
    | python3 -c "import json,sys,re
d=json.load(sys.stdin)
for pr in d:
    for m in re.findall(r'#(\d+)', (pr.get('body') or '')+' '+(pr.get('title') or '')): print(m)" | sort -u)

typeset -A force_ip
for n in ${(s:,:)IN_PROGRESS}; do force_ip[${n// /}]=1; done

set_status() {  # $1=itemID $2=optionID
  if [[ "$DRY_RUN" == "1" ]]; then log "      [dry-run] set status → $2"; return; fi
  gh project item-edit --id "$1" --project-id "$PROJECT_ID" --field-id "$STATUS_FIELD_ID" \
     --single-select-option-id "$2" >/dev/null
}

added=0 moved_ip=0 moved_done=0

# ─── 1. Backfill open issues missing from the board (→ Triaged) ───────────────
log "\n▸ Backfill: open issues missing from the board"
for num in $open_issues; do
  if [[ -z "${item_id[$num]:-}" ]]; then
    title=$(gh issue view "$num" --repo "$REPO" --json title -q .title)
    log "  + #$num → add + Triaged   ($title)"
    if [[ "$DRY_RUN" != "1" ]]; then
      iid=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" \
              --url "https://github.com/$REPO/issues/$num" --format json \
            | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
      item_id[$num]="$iid"; item_status[$num]=""
      set_status "$iid" "$OPT_TRIAGED"
    fi
    ((added++)) || true
  fi
done
[[ $added -eq 0 ]] && log "  (all open issues already carded)"

# ─── 2. Open issues with a linked open PR (or forced) → In Progress ───────────
log "\n▸ In Progress: open issues with a linked open PR (or forced via \$IN_PROGRESS)"
for num in $open_issues; do
  [[ -n "${pr_open[$num]:-}" || -n "${force_ip[$num]:-}" ]] || continue
  [[ -n "${item_id[$num]:-}" ]] || continue
  [[ "${item_status[$num]:-}" == "In Progress" ]] && continue
  why=$([[ -n "${force_ip[$num]:-}" ]] && echo forced || echo "open PR")
  log "  → #$num → In Progress   ($why)"
  set_status "${item_id[$num]}" "$OPT_IN_PROGRESS"; ((moved_ip++)) || true
done
[[ $moved_ip -eq 0 ]] && log "  (none)"

# ─── 3. Closed-COMPLETED issues carded but not Done → Done ────────────────────
log "\n▸ Done: completed-closed issues whose card isn't Done yet"
for num in ${(k)item_id}; do
  [[ "$completed_set" == *" $num "* ]] || continue        # closed as COMPLETED
  [[ "${item_status[$num]:-}" == "Done" ]] && continue     # already Done
  log "  ✓ #$num → Done   (was: ${item_status[$num]:-none})"
  set_status "${item_id[$num]}" "$OPT_DONE"; ((moved_done++)) || true
done
[[ $moved_done -eq 0 ]] && log "  (none)"

# ─── 3b. Flag NOT_PLANNED closed issues that linger in a non-terminal column ──
flagged=0
for num in ${(k)item_id}; do
  [[ "$notplanned_set" == *" $num "* ]] || continue
  [[ "${item_status[$num]:-}" == "Done" ]] && continue
  [[ $flagged -eq 0 ]] && log "\n⚠ NOT_PLANNED (won't-do) closed issues — no matching column; review manually:"
  log "  · #$num  (card: ${item_status[$num]:-none}) — leave, or close out on the board by hand"
  ((flagged++)) || true
done

# ─── 4. GSD drift eyeball (no auto-edit) ──────────────────────────────────────
log "\n▸ GSD source-of-truth (.planning/STATE.md)"
[[ -f .planning/STATE.md ]] && grep -E "^(Phase|Status):" .planning/STATE.md | sed 's/^/    /' || true

log "\n✓ Done — added $added, →In Progress $moved_ip, →Done $moved_done."
