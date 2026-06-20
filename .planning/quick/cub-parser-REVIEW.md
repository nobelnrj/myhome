---
phase: quick-cub-parser
reviewed: 2026-06-04T20:04:01Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - MyHomeApp/Features/Ingestion/CUBParser.swift
  - MyHomeApp/Features/Gmail/GmailSyncController.swift
  - MyHomeTests/CUBParserTests.swift
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Quick: CUBParser Code Review Report

**Reviewed:** 2026-06-04T20:04:01Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Reviewed the new `CUBParser` (City Union Bank email parser), the two-line change to
`GmailSyncController` (parser registration + Gmail sender filter), and the 10 unit tests.
The parser is a faithful structural copy of `HDFCParser`/`ICICIParser` and the test suite is
green against the confirmed 06-05 debit fixture.

No BLOCKER-class defects were found: the registration lines are correct, money is handled with
`Decimal` (not `Double`), reversal sign handling is consistent with HDFC, and `canHandle`
correctly rejects non-CUB senders and blocked subjects.

The concerns are robustness / correctness-under-drift issues, not failures against the current
corpus. The most important is that `extractVisibleText` directly contradicts its own
documentation and is fragile against any future CUB HTML that wraps its body in an `<html>` tag
(the current fixture happens to start with `<div>`, which is why tests pass). I also flag a
latent quoted-printable UTF-8 decoding bug inherited from `HDFCParser`. Because the credit/reversal
path is admittedly speculative (no real corpus), it is the least-tested surface and deserves the
robustness fixes below before it ever fires on real mail.

## Warnings

### WR-01: `extractVisibleText` contradicts its own doc and discards the text/plain section if an `<html>` tag is ever present

**File:** `MyHomeApp/Features/Ingestion/CUBParser.swift:175-185`

**Issue:** The doc comment (lines 172-174) states: *"The body lacks a top-level `<html` tag, so the
whole raw message is decoded and stripped — the first regex match is taken from the leading
text/plain section."* But the code does the opposite:

```swift
if let htmlStart = lower.range(of: "<html") {
    htmlContent = String(rawEmail[htmlStart.lowerBound...])
}
```

If a CUB email ever contains an `<html` tag, this slices away everything before it — including the
entire text/plain section the parser is explicitly designed around — and runs all extraction
against the HTML part instead. The current fixture (`cub_savings_debit_1.eml`) starts the HTML
section with `<div>` (no `<html`), so the slice never triggers and tests pass. This is a latent
correctness trap: a templating change on CUB's side (or a forwarded/wrapped message) would silently
switch the parser onto an untested code path where QP soft-line-breaks split tokens differently
(e.g. the merchant string spans `=`-terminated lines in the HTML part), potentially breaking
merchant/amount extraction.

**Fix:** Either honor the documented behavior (do not slice for CUB), or make the slice CUB-aware.
Simplest fix that matches the comment:

```swift
private func extractVisibleText(from rawEmail: String) -> String {
    // CUB emails are multipart/alternative (text/plain first). Decode and strip the
    // whole message; firstMatch() will hit the leading text/plain section.
    let qpDecoded = decodeQuotedPrintable(rawEmail)
    return stripHTMLTags(qpDecoded)
}
```

If the `<html` slice is intentionally retained for symmetry with HDFC, update the doc comment so it
no longer claims the plain section is used, and add a fixture whose HTML part is wrapped in `<html>`
to prove the HTML path also extracts correctly.

### WR-02: Quoted-printable hex escapes are decoded as Latin-1 bytes, not UTF-8 — multi-byte characters corrupt

**File:** `MyHomeApp/Features/Ingestion/CUBParser.swift:216-225`

**Issue:** Each `=XX` escape is converted to a single `Unicode.Scalar` from one byte:

```swift
if let byte = UInt8(hexStr, radix: 16) {
    let scalar = Unicode.Scalar(byte)
    result.append(Character(scalar))   // treats byte as a Latin-1 code point
    ...
}
```

A multi-byte UTF-8 character encoded as consecutive escapes (e.g. the rupee sign `₹` = `=E2=82=B9`)
decodes to three separate garbage scalars (`Â`, `‚`, `¹`) instead of `₹`, because bytes are appended
one at a time as individual scalars rather than being collected and decoded as a UTF-8 byte stream.
The CUB corpus uses the ASCII string `INR`, so this does not bite today, but the parser's docstring
advertises robust QP decoding (lines 187-191), and any CUB merchant name containing a non-ASCII
character would be corrupted. This bug is inherited verbatim from `HDFCParser.decodeQuotedPrintable`
(lines 299-340), so fixing it should be done in both for consistency — flagging here because the
new file re-introduces it.

**Fix:** Accumulate decoded bytes into a `[UInt8]` buffer and decode the whole stream as UTF-8 once,
emitting literal characters as their UTF-8 bytes too. Sketch:

```swift
var bytes: [UInt8] = []
// ... on '=XX': bytes.append(byte)
// ... on soft break: skip
// ... on literal scalar < 0x80: bytes.append(UInt8(sc.value))
//     (or append sc.utf8 for non-ASCII literals)
return String(decoding: bytes, as: UTF8.self)
```

### WR-03: Credit/reversal template fingerprint is too loose given it is unverified against any real corpus

**File:** `MyHomeApp/Features/Ingestion/CUBParser.swift:129-135`

**Issue:** The credit path is admittedly speculative (lines 20-21, 126-128: "added defensively by
symmetry", no confirmed corpus). Its fingerprint is only `credited with INR` + `towards` + `Avl Bal`.
Indian bank credit alerts very commonly include genuine money-in events (salary, interest, inbound
NEFT/UPI from another person) that are NOT reversals. Because the code unconditionally sets
`isReversal: true` and `amount: -abs(amount)` (lines 156, 162) for anything matching this loose
fingerprint, the first real CUB credit email that lands will be silently recorded as a negative
expense/reversal — corrupting balances and category stats with no signal to the user. There is no
disambiguation (HDFC, by contrast, carefully excludes P2P credits via `Sender:` / "has been
successfully credited" guards on lines 234-236).

**Fix:** Until a real CUB credit sample exists, prefer returning `nil` for credits (do not invent
expense rows), or gate the reversal classification behind a confirmed reversal/refund keyword rather
than treating every credit as a reversal. At minimum mirror HDFC's exclusion guards so non-reversal
credits are skipped:

```swift
// Only treat as reversal when an explicit reversal/refund marker is present;
// otherwise skip (do not record speculative negative expenses).
guard body.contains("reversal") || body.contains("refund") || body.contains("reversed") else {
    return nil
}
```

### WR-04: `firstMatch` extraction can cross MIME-part boundaries, risking mismatched amount/merchant/date

**File:** `MyHomeApp/Features/Ingestion/CUBParser.swift:96, 105, 108, 319-320, 337-338`

**Issue:** `extractVisibleText` concatenates the decoded text/plain section and the decoded text/html
section into one string (the `<html` slice doesn't fire for the current fixture — see WR-01). Each
extractor then independently calls `firstMatch` over that combined string. For the confirmed fixture
the plain and html copies are identical, so all `firstMatch` calls land in the plain section and agree.
But the extractors are not anchored to a single occurrence: the amount, merchant, account-tail, and
date regexes each independently take *their own* first match. If the two MIME parts ever differ
(e.g. CUB tweaks wording or amount formatting in only one part, or a multi-transaction digest email
arrives), the amount could be pulled from one part and the merchant/date from another, producing a
silently mismatched expense row. This is a structural fragility of stripping the whole multipart body
into one blob rather than selecting a single part.

**Fix:** Select one MIME part (the text/plain section) before extraction so every regex operates on the
same authoritative text, e.g. slice on the `Content-Type: text/plain` boundary up to the next
`--<boundary>` marker, then decode/strip only that segment. This also resolves WR-01 cleanly.

## Info

### IN-01: Date regex `\w{3}` is broader than the intended month token

**File:** `MyHomeApp/Features/Ingestion/CUBParser.swift:320, 338`

**Issue:** `\d{1,2}-\w{3}-\d{4}` matches any three word-characters (including digits/underscores) as the
"month", e.g. `12-99X-2026`. It is salvaged only because `DateFormatter` rejects non-month tokens and
the function returns `nil`, falling back to the email `Date:` header. Functionally safe but imprecise.

**Fix:** Constrain to letters: `#"\b(\d{1,2}-[A-Za-z]{3}-\d{4})\b"#`.

### IN-02: Amount regex lacks a leading-digit anchor, unlike HDFC

**File:** `MyHomeApp/Features/Ingestion/CUBParser.swift:96, 138`

**Issue:** CUB uses `([\d,]+(?:\.\d{1,2})?)` whereas `HDFCParser` anchors with `\d[\d,]*` to reject a
leading comma. CUB's pattern would accept a malformed `,100` capture. Matches `ICICIParser`'s
convention (`[\d,]+`), so this is a pre-existing house style, not a new defect — noted for awareness.

**Fix (optional, for consistency with HDFC):** `#"debited with INR\s+(\d[\d,]*(?:\.\d{1,2})?)\s+towards"#`.

### IN-03: CUB fixture is duplicated in two directories and could drift

**File:** `MyHomeTests/Fixtures/cub_savings_debit_1.eml` and `MyHomeTests/Resources/Fixtures/cub_savings_debit_1.eml`

**Issue:** Two byte-identical copies of the fixture exist. The test loader resolves `subdirectory: "Fixtures"`,
so only one is authoritative; the duplicate can silently diverge and mislead future maintainers.

**Fix:** Keep a single canonical fixture location and remove the duplicate, or document which directory
is bundled into the test target.

---

_Reviewed: 2026-06-04T20:04:01Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
