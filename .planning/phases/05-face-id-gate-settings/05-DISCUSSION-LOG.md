# Phase 5: Face ID Gate & Settings - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 5-Face ID Gate & Settings
**Areas discussed:** Lock trigger & re-lock, LAError fallback UX, Management placement, Toggle & Settings shell

---

## Lock trigger & re-lock

### When to require authentication
| Option | Description | Selected |
|--------|-------------|----------|
| Launch + background timeout | Auth on cold launch AND on return from background after a grace period | ✓ |
| Cold launch only | Auth only on fresh launch; never re-prompt from background | |
| Every foreground | Auth every foreground, no grace period | |

### Grace period
| Option | Description | Selected |
|--------|-------------|----------|
| ~3 minutes | Short, aggressive re-lock for sensitive financial data | ✓ |
| ~5 minutes | Balanced | |
| Immediate (0s) | Any background → relock | |

### Locked / app-switcher UI
| Option | Description | Selected |
|--------|-------------|----------|
| Blur + unlock screen | Privacy overlay when inactive + dedicated unlock screen with Unlock button | ✓ |
| Unlock screen only | No app-switcher privacy overlay | |
| Auto-prompt, no manual button | Fires Face ID with no escape button (lockout risk) | |

**User's choice:** Launch + ~3 min background timeout; privacy blur + dedicated unlock screen with manual button.

---

## LAError fallback UX

### Authentication policy
| Option | Description | Selected |
|--------|-------------|----------|
| deviceOwnerAuthentication | Face ID then system passcode fallback (SEC-02's policy) | ✓ |
| biometryAny + manual passcode | Biometrics-only + custom passcode path | |

### No biometry but passcode exists
| Option | Description | Selected |
|--------|-------------|----------|
| Fall through to passcode | System auto-falls to passcode; app stays protected | ✓ |
| Disable lock, warn user | Treat as unlocked + Settings banner | |

### No device passcode at all
| Option | Description | Selected |
|--------|-------------|----------|
| Open + nudge to set passcode | Let user in, persistent warning | |
| Hard block | Refuse entry until passcode set | ✓ (refined below) |

### Recoverable failures / dismissal
| Option | Description | Selected |
|--------|-------------|----------|
| Stay locked + Retry button | Remain on unlock screen with visible retry; passcode hint on lockout | ✓ |
| Auto-retry immediately | Re-fire prompt on failure (loop risk) | |

**User's choice:** `deviceOwnerAuthentication`; fall through to passcode when no biometry; hard block when no passcode; stay-locked-with-retry on recoverable errors.

### Refinement — no-passcode hard block strictness (flagged SEC-02 lockout tension)
| Option | Description | Selected |
|--------|-------------|----------|
| Hard block + reachable escape | Block but guide user to set device passcode; re-evaluate on foreground; data preserved, no reinstall | ✓ |
| Pure hard block | No in-app escape | |
| Reconsider → open + nudge | Switch to letting user in with warning | |

**Notes:** Claude flagged that a pure hard block on a passcode-less device contradicts SEC-02's "never lock the user out" (only escape would be reinstall → data loss). User chose to keep the block but add a reachable, data-preserving escape.

---

## Management placement

### Where category + budget management lives
| Option | Description | Selected |
|--------|-------------|----------|
| Mirror (both entry points) | Keep on Budgets tab + add to Settings, reuse same views | partial |
| Relocate (Settings only) | Move all management to Settings; Budgets view-only | |
| Relocate categories, mirror budgets | Categories to Settings; budgets reachable from cards + Settings | |

**User's choice (free text):** "Budget is a bigger screen and should have its own separate screen. Don't pollute settings. Settings should have a button that allows the user to add/manage categories. That's it. Budget editing should remain in the budget screen."

### SET-03 reconciliation (flagged: requirement says "manage budgets from Settings")
| Option | Description | Selected |
|--------|-------------|----------|
| Reinterpret SET-03 (budgets on Budgets tab) | Treat existing Budgets-tab editing as satisfying SET-03; update roadmap wording | |
| Add a thin 'Budgets' link in Settings | Settings row deep-links to Budgets tab; no budget UI duplicated | ✓ |

**Notes:** Claude surfaced that SET-03 / ROADMAP SC#3 say budgets manageable "from Settings." User keeps budget editing on the Budgets screen and adds a thin Settings→Budgets link to honor the literal wording.

---

## Toggle & Settings shell

### Enable behavior
| Option | Description | Selected |
|--------|-------------|----------|
| Auth to confirm on enable | Toggle ON triggers auth; enables only on success | ✓ |
| Enable instantly | Sets flag; first challenge on next launch | |

### Disable behavior
| Option | Description | Selected |
|--------|-------------|----------|
| Require auth to disable | Toggle OFF prompts auth first | ✓ |
| Disable instantly | No challenge | |

### Toggle storage
| Option | Description | Selected |
|--------|-------------|----------|
| App Group UserDefaults | Shared App Group suite (preference, not secret) | ✓ |
| Standard UserDefaults | UserDefaults.standard | |

### Settings shell content
| Option | Description | Selected |
|--------|-------------|----------|
| Minimal + About row | Three functional items + About/version footer; clean for P6 | ✓ |
| Add disabled Gmail placeholder | Greyed-out "coming soon" row | |
| Bare minimum | Only the three items | |

**User's choice:** Auth-to-enable + auth-to-disable; App Group UserDefaults; minimal shell with About/version footer.

---

## Claude's Discretion

- Settings tab icon + label (e.g., `gearshape` / "Settings").
- Exact grace-period constant (start 180s) and the scene-phase / lifecycle seam where the gate hooks in.
- The `LAContext` protocol-port test seam (mirror Phase 3's `NotificationCenterPort`/`SpyCenter`).
- Sheet vs NavigationLink presentation of the category entry in Settings.
- Unlock-screen copy, no-passcode guidance copy, `.biometryLockout` hint copy (UI-SPEC).
- About/version footer content.

## Deferred Ideas

- Gmail section in Settings (connect / sign-out / last-synced / Sync now) → Phase 6.
- Custom in-app PIN / app-specific passcode → out (device passcode only).
- Per-record / per-note encryption → out of charter.
- Configurable (user-tunable) auto-lock timeout → not v1.
- Biometric re-auth for individual sensitive actions → not in scope.
