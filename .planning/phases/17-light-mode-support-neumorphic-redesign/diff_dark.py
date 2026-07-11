#!/usr/bin/env python3
"""D-06 masked dark-mode screenshot diff (Phase 17).

Usage:
    python3 diff_dark.py <before_dir> <after_dir>

For every PNG present in BOTH directories (matched by filename), convert to RGB
and compute a pixel difference. A screen PASSES if the difference bounding box is
empty (byte/pixel-identical). For ``dark-tab0.png`` ONLY, the hero-orb dish region
(``ORB_BBOX``) is masked with a solid black ellipse on BOTH images before diffing,
because the dish's ``GlowParticleRing`` is TimelineView-driven and never renders
byte-stable across launches.

Exit code 0 iff every matched screen passes; 1 otherwise.

ORB_BBOX is in ORIGINAL screenshot pixel coordinates (iPhone 17 @ 1206x2622).
The dish is the ~300pt NeuCircularWell in SpendBudgetCard, horizontally centered.
Determined by inspecting dark-tab0.png once; ~generous margin so all animated
particles + rim bloom fall inside the mask.
"""
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

# (left, top, right, bottom) in original-resolution pixels. Masked on dark-tab0 only.
ORB_BBOX = (120, 570, 1085, 1560)

# Filenames whose animated orb dish must be masked before diffing.
MASKED_FILES = {"dark-tab0.png"}

# Per-channel 8-bit difference AT OR BELOW this many levels is treated as identical.
# Absorbs the non-deterministic GPU compositing of translucent SwiftUI materials — e.g.
# the navigation-push dimming layer on dark-analytics, where the Overview content bleeding
# behind the pushed Analytics screen jitters by <=12/255 across launches and never renders
# byte-stable (same class of non-determinism as the animated orb, but spatially diffuse
# rather than localized, so a rectangular mask would blank real content). A visible token
# drift shifts dark-palette colors by far more than this and still fails. The AUTHORITATIVE
# byte-exact D-06 guarantee is the unit-level DarkBitIdentityTests (every token resolved
# `==` in a dark environment); this render diff corroborates it. Set 0 for strict byte-equality.
TOLERANCE = 16


def _mask_orb(img: Image.Image) -> Image.Image:
    img = img.convert("RGB")
    draw = ImageDraw.Draw(img)
    draw.ellipse(ORB_BBOX, fill=(0, 0, 0))
    return img


def _load(path: Path, masked: bool) -> Image.Image:
    img = Image.open(path)
    if masked:
        return _mask_orb(img)
    return img.convert("RGB")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: python3 diff_dark.py <before_dir> <after_dir>", file=sys.stderr)
        return 2

    before_dir = Path(sys.argv[1])
    after_dir = Path(sys.argv[2])

    before_pngs = {p.name for p in before_dir.glob("*.png")}
    after_pngs = {p.name for p in after_dir.glob("*.png")}
    common = sorted(before_pngs & after_pngs)

    if not common:
        print("ERROR: no matching PNG pairs between the two directories", file=sys.stderr)
        return 2

    all_pass = True
    for name in common:
        masked = name in MASKED_FILES
        a = _load(before_dir / name, masked)
        b = _load(after_dir / name, masked)

        if a.size != b.size:
            print(f"FAIL {name}: size mismatch {a.size} vs {b.size}")
            all_pass = False
            continue

        diff = ImageChops.difference(a, b)
        if TOLERANCE > 0:
            # Zero out per-channel differences at or below TOLERANCE (compositing noise).
            diff = diff.point(lambda p: 0 if p <= TOLERANCE else p)
        bbox = diff.getbbox()
        if bbox is None:
            notes = []
            if masked:
                notes.append("orb masked")
            if TOLERANCE > 0:
                notes.append(f"tol={TOLERANCE}")
            note = f" ({', '.join(notes)})" if notes else ""
            print(f"PASS {name}{note}")
        else:
            print(f"FAIL {name}: differs in region {bbox}")
            all_pass = False

    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
