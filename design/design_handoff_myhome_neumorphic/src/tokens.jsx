// tokens.jsx — MyHome design system.
// One yellow-forward accent system, six interchangeable UI "skins" that the same
// components render through:  Liquid Glass · Glassmorphism · Neomorphism ·
// Minimalism · Bento Grid · Spatial.  Each skin redefines surface/material tokens
// so every screen re-skins from a single tweak.

const SF = '-apple-system, "SF Pro Display", "SF Pro Text", "SF Pro", system-ui, sans-serif';

// hex -> rgba
function hexa(hex, a) {
  const h = hex.replace('#', '');
  const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r},${g},${b},${a})`;
}

// ── Accent pairs — yellow is the brand. pos = income/up, neg = spend/down, glow = brand yellow ──
const ACCENT_PAIRS = {
  Amber:  { pos: '#34E29B', neg: '#FF6B6B', glow: '#FFD60A' }, // signature canary yellow
  Citrus: { pos: '#A3E635', neg: '#FB7185', glow: '#FACC15' }, // warmer gold
  Honey:  { pos: '#5EEAD4', neg: '#F8845A', glow: '#FFB400' }, // amber-orange
};

// ── Ambient plasma palettes — kept cool/deep so the yellow UI pops against them ──
const BLOB_PALETTES = {
  Nebula: ['#1A0533', '#04243D', '#003D2E'], // violet · deep blue · teal
  Ember:  ['#2A0610', '#240A3D', '#3A1A00'], // crimson · plum · amber
  Abyss:  ['#04243D', '#0A0A3A', '#003A33'], // blue · navy · jade
};

// Luminous category palette — varied, distinct from the brand yellow.
const CAT_COLORS = {
  groceries:     '#2DD4BF',
  dining:        '#FB923C',
  fuel:          '#F472B6',
  utilities:     '#7DD3FC',
  rent:          '#818CF8',
  auto:          '#38BDF8',
  shopping:      '#E879F9',
  health:        '#A78BFA',
  subscriptions: '#22D3EE',
  entertainment: '#C084FC',
  other:         '#94A3B8',
};

// spring-ish easings
const SPRING = 'cubic-bezier(.34,1.32,.42,1)';
const SPRING_SOFT = 'cubic-bezier(.32,.72,0,1)';

function heroGradient() {
  return 'radial-gradient(120% 120% at 0% 0%, color-mix(in srgb, var(--glow) 22%, transparent) 0%, transparent 55%), radial-gradient(120% 120% at 100% 100%, color-mix(in srgb, var(--neg) 16%, transparent) 0%, transparent 55%)';
}

// ── Per-style metadata (consumed by the shell) ──
const STYLE_META = {
  liquid:  { label: 'Liquid Glass', plasma: true,  light: false, blob: 'Nebula' },
  glass:   { label: 'Glassmorphism', plasma: true, light: false, blob: 'Abyss' },
  neuro:   { label: 'Neomorphism',  plasma: false, light: false, blob: 'Nebula' },
  minimal: { label: 'Minimalism',   plasma: false, light: true,  blob: 'Nebula' },
  bento:   { label: 'Bento Grid',   plasma: false, light: false, blob: 'Nebula' },
  spatial: { label: 'Spatial',      plasma: true,  light: false, blob: 'Abyss' },
};
const STYLE_ORDER = ['liquid', 'glass', 'neuro', 'minimal', 'bento', 'spatial'];

function buildThemeVars(opts) {
  const { style = 'liquid', pair = ACCENT_PAIRS.Amber, blur = 24, alpha = 1 } = opts || {};
  const pos = pair.pos, neg = pair.neg, glow = pair.glow;
  const meta = STYLE_META[style] || STYLE_META.liquid;

  // On the light skin, pure canary yellow can't carry as a text/icon colour —
  // deepen it to a legible gold while keeping the vivid yellow for glow effects.
  const accentCol = meta.light ? 'color-mix(in srgb, ' + glow + ' 72%, #4a3500)' : glow;

  const accent = {
    '--accent': accentCol, '--accent-soft': hexa(glow, meta.light ? 0.22 : 0.16),
    '--pos': pos, '--green': pos,
    '--neg': neg, '--red': neg,
    '--orange': '#FFB020', '--glow': glow,
  };

  let surf;
  switch (style) {

    // ── Glassmorphism — vivid, lighter frost, bright rims, big blur ──
    case 'glass':
      surf = {
        '--label': '#FFFFFF',
        '--label2': 'rgba(232,236,255,0.66)',
        '--label3': 'rgba(232,236,255,0.36)',
        '--label4': 'rgba(232,236,255,0.18)',
        '--bg': '#0B1022', '--bg-grouped': 'transparent', '--bg-elevated': 'transparent',
        '--bg-elevated2': 'rgba(255,255,255,0.16)',
        '--fill': 'rgba(255,255,255,0.16)', '--fill2': 'rgba(255,255,255,0.11)', '--fill3': 'rgba(255,255,255,0.08)',
        '--sep': 'rgba(255,255,255,0.14)', '--sep-opaque': 'rgba(255,255,255,0.16)',
        '--glass-tint': hexa('#ffffff', 0.11 * alpha),
        '--glass-tint-strong': hexa('#ffffff', 0.17 * alpha),
        '--glass-blur': `saturate(165%) blur(${blur + 6}px)`,
        '--glass-border': '1px solid rgba(255,255,255,0.30)',
        '--glass-rim': 'inset 0 1px 0 rgba(255,255,255,0.55), inset 0 0 0.5px rgba(255,255,255,0.35)',
        '--glass-shadow': 'inset 0 1px 0 rgba(255,255,255,0.30), 0 10px 30px rgba(0,0,0,0.34)',
        '--glass-shadow-float': 'inset 0 1px 0 rgba(255,255,255,0.45), 0 26px 64px rgba(0,0,0,0.5)',
        '--card-shadow': 'inset 0 1px 0 rgba(255,255,255,0.26), 0 14px 40px rgba(0,0,0,0.34)',
        '--card-radius': '22px',
        '--chrome': 'rgba(11,16,34,0.42)', '--chrome-blur': `saturate(165%) blur(${blur + 6}px)`,
        '--ambient': 'none', '--hero-gradient': heroGradient(),
        '--hero-shadow': '0 24px 60px rgba(0,0,0,0.42)', '--device-bg': '#0B1022',
      };
      break;

    // ── Neomorphism — soft, opaque charcoal, dual extruded shadow, no blur ──
    case 'neuro':
      surf = {
        '--label': '#ECEDF4',
        '--label2': 'rgba(220,223,238,0.56)',
        '--label3': 'rgba(220,223,238,0.32)',
        '--label4': 'rgba(220,223,238,0.16)',
        '--bg': '#1C1C23', '--bg-grouped': 'transparent', '--bg-elevated': 'transparent',
        '--bg-elevated2': '#262630',
        '--fill': '#16161C', '--fill2': '#191920', '--fill3': '#15151B',
        '--sep': 'rgba(255,255,255,0.05)', '--sep-opaque': 'rgba(0,0,0,0.30)',
        '--glass-tint': '#1F1F27',
        '--glass-tint-strong': '#22222C',
        '--glass-blur': 'none',
        '--glass-border': '1px solid rgba(255,255,255,0.025)',
        '--glass-rim': 'inset 1px 1px 1px rgba(255,255,255,0.045), inset -1px -1px 1px rgba(0,0,0,0.30)',
        '--glass-shadow': '-6px -6px 14px rgba(255,255,255,0.035), 7px 7px 18px rgba(0,0,0,0.55)',
        '--glass-shadow-float': '-9px -9px 22px rgba(255,255,255,0.04), 11px 11px 28px rgba(0,0,0,0.62)',
        '--card-shadow': '-6px -6px 14px rgba(255,255,255,0.035), 7px 7px 18px rgba(0,0,0,0.52)',
        '--card-radius': '26px',
        '--chrome': '#1C1C23', '--chrome-blur': 'none',
        '--ambient': 'none', '--hero-gradient': heroGradient(),
        '--hero-shadow': '7px 7px 18px rgba(0,0,0,0.5)', '--device-bg': '#1C1C23',
      };
      break;

    // ── Minimalism — warm paper, flat, hairline, no blur/shadow ──
    case 'minimal':
      surf = {
        '--label': '#1A1813',
        '--label2': 'rgba(40,36,26,0.56)',
        '--label3': 'rgba(40,36,26,0.34)',
        '--label4': 'rgba(40,36,26,0.14)',
        '--bg': '#F4F2EA', '--bg-grouped': 'transparent', '--bg-elevated': 'transparent',
        '--bg-elevated2': '#FFFFFF',
        '--fill': 'rgba(30,26,16,0.065)', '--fill2': 'rgba(30,26,16,0.05)', '--fill3': 'rgba(30,26,16,0.045)',
        '--sep': 'rgba(30,26,16,0.10)', '--sep-opaque': 'rgba(30,26,16,0.12)',
        '--glass-tint': '#FBFAF4',
        '--glass-tint-strong': '#FFFFFF',
        '--glass-blur': 'none',
        '--glass-border': '1px solid rgba(30,26,16,0.09)',
        '--glass-rim': 'none',
        '--glass-shadow': 'none',
        '--glass-shadow-float': '0 10px 30px rgba(40,36,26,0.10)',
        '--card-shadow': 'none',
        '--card-radius': '16px',
        '--chrome': 'rgba(244,242,234,0.82)', '--chrome-blur': 'saturate(120%) blur(14px)',
        '--ambient': 'none', '--hero-gradient': heroGradient(),
        '--hero-shadow': '0 10px 30px rgba(40,36,26,0.10)', '--device-bg': '#F4F2EA',
      };
      break;

    // ── Bento Grid — opaque dark tiles, soft borders, modular, subtle yellow wash ──
    case 'bento':
      surf = {
        '--label': '#FFFFFF',
        '--label2': 'rgba(228,232,255,0.58)',
        '--label3': 'rgba(228,232,255,0.32)',
        '--label4': 'rgba(228,232,255,0.16)',
        '--bg': '#0B0B12', '--bg-grouped': 'transparent', '--bg-elevated': 'transparent',
        '--bg-elevated2': '#23232D',
        '--fill': 'rgba(255,255,255,0.07)', '--fill2': 'rgba(255,255,255,0.05)', '--fill3': 'rgba(255,255,255,0.04)',
        '--sep': 'rgba(255,255,255,0.07)', '--sep-opaque': 'rgba(255,255,255,0.09)',
        '--glass-tint': '#16161E',
        '--glass-tint-strong': '#1A1A23',
        '--glass-blur': 'none',
        '--glass-border': '1px solid rgba(255,255,255,0.08)',
        '--glass-rim': 'inset 0 1px 0 rgba(255,255,255,0.05)',
        '--glass-shadow': '0 2px 12px rgba(0,0,0,0.40)',
        '--glass-shadow-float': '0 10px 28px rgba(0,0,0,0.52)',
        '--card-shadow': '0 2px 12px rgba(0,0,0,0.38)',
        '--card-radius': '22px',
        '--chrome': 'rgba(11,11,18,0.72)', '--chrome-blur': 'saturate(120%) blur(18px)',
        '--ambient': 'radial-gradient(120% 60% at 100% -8%, color-mix(in srgb, var(--glow) 8%, transparent), transparent 60%)',
        '--hero-gradient': heroGradient(),
        '--hero-shadow': '0 10px 28px rgba(0,0,0,0.5)', '--device-bg': '#0B0B12',
      };
      break;

    // ── Spatial — visionOS: ultra-translucent, huge blur, deep float, big radius ──
    case 'spatial':
      surf = {
        '--label': '#FFFFFF',
        '--label2': 'rgba(232,236,255,0.62)',
        '--label3': 'rgba(232,236,255,0.34)',
        '--label4': 'rgba(232,236,255,0.16)',
        '--bg': '#0A0A11', '--bg-grouped': 'transparent', '--bg-elevated': 'transparent',
        '--bg-elevated2': 'rgba(255,255,255,0.12)',
        '--fill': 'rgba(255,255,255,0.12)', '--fill2': 'rgba(255,255,255,0.08)', '--fill3': 'rgba(255,255,255,0.055)',
        '--sep': 'rgba(255,255,255,0.10)', '--sep-opaque': 'rgba(255,255,255,0.12)',
        '--glass-tint': hexa('#ffffff', 0.07 * alpha),
        '--glass-tint-strong': hexa('#ffffff', 0.12 * alpha),
        '--glass-blur': `saturate(150%) blur(${blur + 14}px)`,
        '--glass-border': '1px solid rgba(255,255,255,0.18)',
        '--glass-rim': 'inset 0 1px 0 rgba(255,255,255,0.38), inset 0 0 0.5px rgba(255,255,255,0.25)',
        '--glass-shadow': 'inset 0 1px 0 rgba(255,255,255,0.20), 0 20px 56px rgba(0,0,0,0.6)',
        '--glass-shadow-float': 'inset 0 1px 0 rgba(255,255,255,0.32), 0 44px 104px rgba(0,0,0,0.74)',
        '--card-shadow': 'inset 0 1px 0 rgba(255,255,255,0.18), 0 32px 76px rgba(0,0,0,0.6)',
        '--card-radius': '30px',
        '--chrome': 'rgba(10,10,17,0.38)', '--chrome-blur': `saturate(150%) blur(${blur + 14}px)`,
        '--ambient': 'none', '--hero-gradient': heroGradient(),
        '--hero-shadow': '0 40px 100px rgba(0,0,0,0.66)', '--device-bg': '#0A0A11',
      };
      break;

    // ── Liquid Glass (default) — void canvas, translucent glass, plasma ──
    case 'liquid':
    default:
      surf = {
        '--label': '#FFFFFF',
        '--label2': 'rgba(226,232,255,0.60)',
        '--label3': 'rgba(226,232,255,0.32)',
        '--label4': 'rgba(226,232,255,0.16)',
        '--bg': '#07070E', '--bg-grouped': 'transparent', '--bg-elevated': 'transparent',
        '--bg-elevated2': 'rgba(255,255,255,0.07)',
        '--fill': 'rgba(255,255,255,0.11)', '--fill2': 'rgba(255,255,255,0.075)', '--fill3': 'rgba(255,255,255,0.055)',
        '--sep': 'rgba(255,255,255,0.07)', '--sep-opaque': 'rgba(255,255,255,0.09)',
        '--glass-tint': hexa('#ffffff', 0.05 * alpha),
        '--glass-tint-strong': hexa('#ffffff', 0.085 * alpha),
        '--glass-blur': `saturate(135%) blur(${blur}px)`,
        '--glass-border': '1px solid rgba(255,255,255,0.08)',
        '--glass-rim': 'inset 0 1px 0 rgba(255,255,255,0.16), inset 0 0 0.5px rgba(255,255,255,0.10)',
        '--glass-shadow': 'inset 0 1px 0 rgba(255,255,255,0.11), 0 8px 24px rgba(0,0,0,0.42)',
        '--glass-shadow-float': 'inset 0 1px 0 rgba(255,255,255,0.18), 0 22px 56px rgba(0,0,0,0.62)',
        '--card-shadow': 'inset 0 1px 0 rgba(255,255,255,0.10), 0 16px 38px rgba(0,0,0,0.45)',
        '--card-radius': '24px',
        '--chrome': 'rgba(7,7,14,0.55)', '--chrome-blur': `saturate(135%) blur(${blur}px)`,
        '--ambient': 'none', '--hero-gradient': heroGradient(),
        '--hero-shadow': '0 22px 60px rgba(0,0,0,0.5)', '--device-bg': '#07070E',
      };
      break;
  }

  return { ...accent, ...surf };
}

Object.assign(window, {
  ACCENT_PAIRS, BLOB_PALETTES, CAT_COLORS, STYLE_META, STYLE_ORDER, buildThemeVars, heroGradient,
  hexa, SF, SPRING, SPRING_SOFT,
});
