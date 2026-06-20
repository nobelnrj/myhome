// analytics.jsx — Futuristic Liquid UI · Analytics screen.
// Liquid ink tab underline, flowing area chart (left→right draw + scanning dot),
// staggered liquid category bars with elastic press + glass tooltip,
// frosted AI insight card with typewriter reveal + breathing orb,
// scroll-driven parallax ambient blobs.
const { useState: aS, useEffect: aE, useRef: aR, useLayoutEffect: aLE, useMemo: aMo } = React;

// ════════════════════════════════════════════════════════════════════
// Demo data per time-range
// ════════════════════════════════════════════════════════════════════
const RANGES = ['Week', 'Month', 'Year'];

const SERIES = {
  Week: {
    total: 8420, deltaPct: -6.2, vs: 'vs last week',
    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    values: [820, 1340, 690, 1180, 2240, 1460, 690],
    cats: [
      { id: 'groceries', amount: 2380 },
      { id: 'dining',    amount: 1920 },
      { id: 'fuel',      amount: 1450 },
      { id: 'shopping',  amount: 1340 },
      { id: 'auto',      amount: 780 },
      { id: 'subscriptions', amount: 550 },
    ],
    insight: 'Dining is up 34% this week — three weekend orders drove most of it. Skipping one keeps you under budget.',
  },
  Month: {
    total: 34280, deltaPct: 8.4, vs: 'vs last month',
    labels: ['W1', 'W2', 'W3', 'W4', 'W5'],
    values: [6200, 9100, 5400, 8800, 4780],
    cats: [
      { id: 'rent',      amount: 12000 },
      { id: 'groceries', amount: 6840 },
      { id: 'dining',    amount: 4920 },
      { id: 'shopping',  amount: 4310 },
      { id: 'fuel',      amount: 3210 },
      { id: 'utilities', amount: 3000 },
    ],
    insight: 'You spent ₹4,920 on dining — 14% of the month. That is your fastest-growing category since March.',
  },
  Year: {
    total: 412600, deltaPct: 2.1, vs: 'vs last year',
    labels: ['J','F','M','A','M','J','J','A','S','O','N','D'],
    values: [28000, 31000, 26500, 38000, 33500, 41000, 29000, 35500, 30000, 44000, 39500, 36600],
    cats: [
      { id: 'rent',      amount: 144000 },
      { id: 'groceries', amount: 78400 },
      { id: 'dining',    amount: 52600 },
      { id: 'shopping',  amount: 48200 },
      { id: 'fuel',      amount: 41800 },
      { id: 'health',    amount: 28900 },
    ],
    insight: 'Your savings rate climbed to 31% this year. October was the only month you exceeded your spending cap.',
  },
};

// ════════════════════════════════════════════════════════════════════
// Scroll-parallax ambient — blobs drift with scroll for depth
// ════════════════════════════════════════════════════════════════════
function ParallaxAmbient({ palette, scrollY }) {
  // each blob has its own depth factor (slower = deeper)
  const blobs = [
    { c: palette[0], w: 440, h: 440, left: '-30%', top: '-6%',  depth: 0.16, anim: 'lqAmbA 26s ease-in-out infinite' },
    { c: palette[1], w: 500, h: 500, right: '-34%', bottom: '14%', depth: 0.40, anim: 'lqAmbB 32s ease-in-out infinite' },
    { c: palette[2], w: 360, h: 360, left: '40%',  top: '36%',  depth: 0.26, anim: 'lqAmbA 38s ease-in-out infinite reverse' },
  ];
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: 'var(--bg)', pointerEvents: 'none', zIndex: 0 }}>
      {blobs.map((b, i) => (
        <div key={i} style={{
          position: 'absolute', width: b.w, height: b.h, left: b.left, right: b.right, top: b.top, bottom: b.bottom,
          transform: `translateY(${-scrollY * b.depth}px)`, willChange: 'transform' }}>
          <div className="lq-ambblob" style={{
            position: 'absolute', inset: 0, borderRadius: '50%',
            background: `radial-gradient(circle at 50% 50%, ${b.c} 0%, ${b.c} 26%, transparent 70%)`,
            filter: 'blur(74px)', opacity: 0.6, mixBlendMode: 'screen', animation: b.anim }} />
        </div>
      ))}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(5,6,15,0.30)' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(130% 70% at 50% 118%, rgba(0,0,0,0.42), transparent 55%)' }} />
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Liquid ink tab underline — stretches & morphs as it slides
// ════════════════════════════════════════════════════════════════════
function LiquidTabs({ ranges, active, onChange }) {
  const wrap = aR(null);
  const refs = aR([]);
  const [geom, setGeom] = aS(null);
  const prevIdx = aR(ranges.indexOf(active));

  const measure = () => {
    const w = wrap.current, b = refs.current[ranges.indexOf(active)];
    if (!w || !b) return;
    const wr = w.getBoundingClientRect(), br = b.getBoundingClientRect();
    const s = wr.width / w.offsetWidth || 1; // undo device scale
    setGeom({ left: (br.left - wr.left) / s, right: (wr.right - br.right) / s });
  };
  aLE(measure, [active]);
  aE(() => { const on = () => measure(); window.addEventListener('resize', on); return () => window.removeEventListener('resize', on); }, [active]);

  const idx = ranges.indexOf(active);
  const movingRight = idx > prevIdx.current;
  prevIdx.current = idx;
  // dual-edge timing: the leading edge moves faster so the ink stretches mid-flight
  const fast = '0.40s cubic-bezier(.34,1.46,.44,1)';
  const slow = '0.62s cubic-bezier(.34,1.32,.44,1)';
  const leftT = movingRight ? slow : fast;
  const rightT = movingRight ? fast : slow;

  return (
    <div ref={wrap} style={{ position: 'relative', display: 'flex', gap: 6, padding: 5, margin: '0 18px', borderRadius: 18,
      background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)',
      border: 'var(--glass-border)', boxShadow: 'var(--glass-shadow)', isolation: 'isolate' }}>
      {/* liquid ink underline */}
      <div aria-hidden style={{ position: 'absolute', top: 5, bottom: 5, left: geom ? geom.left : 0, right: geom ? geom.right : 0,
        borderRadius: 13, zIndex: 0, opacity: geom ? 1 : 0,
        background: 'linear-gradient(120deg, color-mix(in srgb, var(--neg) 92%, var(--glow)), color-mix(in srgb, var(--glow) 78%, var(--neg)))',
        boxShadow: '0 0 18px color-mix(in srgb, var(--neg) 55%, transparent), inset 0 1px 0 rgba(255,255,255,0.35)',
        transition: `left ${leftT}, right ${rightT}, opacity .3s` }}>
        <div style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', pointerEvents: 'none',
          background: 'linear-gradient(180deg, rgba(255,255,255,0.28), rgba(255,255,255,0) 55%)' }} />
      </div>
      {ranges.map((r, i) => {
        const on = r === active;
        return (
          <button key={r} ref={el => refs.current[i] = el} className="tap" onClick={() => onChange(r)} style={{
            position: 'relative', zIndex: 1, flex: 1, border: 'none', background: 'none', cursor: 'pointer',
            padding: '10px 0', borderRadius: 13, fontFamily: SF, fontSize: 14.5, fontWeight: on ? 700 : 560,
            letterSpacing: 0.2, color: on ? '#05060F' : 'var(--label2)', transition: 'color .3s' }}>
            {r}
          </button>
        );
      })}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Smooth area chart path (Catmull-Rom → bezier)
// ════════════════════════════════════════════════════════════════════
function buildPath(values, w, h, pad) {
  const n = values.length;
  const max = Math.max(...values) * 1.18 || 1;
  const xs = i => pad + (w - 2 * pad) * (i / (n - 1));
  const ys = v => h - pad - (h - 2 * pad) * (v / max);
  const pts = values.map((v, i) => [xs(i), ys(v)]);
  let d = `M ${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] || pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2] || p2;
    const c1x = p1[0] + (p2[0] - p0[0]) / 6, c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6, c2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += ` C ${c1x.toFixed(2)} ${c1y.toFixed(2)} ${c2x.toFixed(2)} ${c2y.toFixed(2)} ${p2[0].toFixed(2)} ${p2[1].toFixed(2)}`;
  }
  const area = d + ` L ${pts[n - 1][0].toFixed(2)} ${h} L ${pts[0][0].toFixed(2)} ${h} Z`;
  return { line: d, area, pts, max };
}

// ════════════════════════════════════════════════════════════════════
// Hero liquid area chart
// ════════════════════════════════════════════════════════════════════
function AreaChart({ data, rangeKey }) {
  const W = 330, H = 168, PAD = 14;
  const { line, area, pts } = aMo(() => buildPath(data.values, W, H, PAD), [rangeKey]);
  const uid = aMo(() => 'ac' + Math.random().toString(36).slice(2, 7), []);
  const lineRef = aR(null);
  const [len, setLen] = aS(null);
  const [drawn, setDrawn] = aS(false);
  aLE(() => { if (lineRef.current) setLen(lineRef.current.getTotalLength()); }, []);
  aE(() => {
    const t = requestAnimationFrame(() => requestAnimationFrame(() => setDrawn(true)));
    return () => cancelAnimationFrame(t);
  }, []);
  const peakIdx = data.values.indexOf(Math.max(...data.values));

  return (
    <div style={{ position: 'relative' }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: 'block', overflow: 'visible' }} preserveAspectRatio="none">
        <defs>
          {/* flowing vertical gradient — coral at peaks → transparent at base, drifts over 4s */}
          <linearGradient id={uid + 'fill'} x1="0" y1={-24} x2="0" y2={H + 8} gradientUnits="userSpaceOnUse">
            <stop offset="0%"  stopColor="var(--neg)" stopOpacity="0.6" />
            <stop offset="45%" stopColor="var(--neg)" stopOpacity="0.18" />
            <stop offset="100%" stopColor="var(--neg)" stopOpacity="0" />
            <animateTransform attributeName="gradientTransform" type="translate"
              values="0 -16; 0 16; 0 -16" dur="4s" repeatCount="indefinite" calcMode="spline"
              keyTimes="0;0.5;1" keySplines="0.45 0 0.55 1; 0.45 0 0.55 1" />
          </linearGradient>
          <linearGradient id={uid + 'line'} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%"  stopColor="var(--glow)" />
            <stop offset="48%" stopColor="var(--neg)" />
            <stop offset="100%" stopColor="#FFD9E2" />
          </linearGradient>
        </defs>

        {/* baseline grid */}
        {[0.5, 1].map((f, i) => (
          <line key={i} x1={PAD} x2={W - PAD} y1={PAD + (H - 2 * PAD) * f} y2={PAD + (H - 2 * PAD) * f}
            stroke="var(--sep)" strokeWidth="1" strokeDasharray="2 5" />
        ))}

        {/* area fill — fades up as the line draws */}
        <path d={area} fill={`url(#${uid}fill)`}
          style={{ opacity: drawn ? 1 : 0, transition: 'opacity .8s ease .05s' }} />
        {/* smooth glowing line, draws left→right via dashoffset */}
        <path ref={lineRef} d={line} fill="none" stroke={`url(#${uid}line)`} strokeWidth="3" strokeLinecap="round"
          style={{
            strokeDasharray: len || undefined,
            strokeDashoffset: len == null ? 0 : (drawn ? 0 : len),
            transition: 'stroke-dashoffset .8s cubic-bezier(.4,0,.2,1)',
            filter: 'drop-shadow(0 0 5px var(--neg)) drop-shadow(0 1px 3px rgba(0,0,0,0.4))' }} />

        {/* peak marker */}
        <circle cx={pts[peakIdx][0]} cy={pts[peakIdx][1]} r="3.4" fill="#fff"
          style={{ filter: 'drop-shadow(0 0 6px var(--neg))', opacity: drawn ? 1 : 0, transition: 'opacity .4s .7s' }} />

        {/* scanning dot travelling along the line, continuous + soft pulse glow */}
        <g>
          <circle r="9" fill="var(--neg)" style={{ animation: 'lqaDotPulse 1.6s ease-out infinite', transformOrigin: 'center', transformBox: 'fill-box' }}>
            <animateMotion dur="3.6s" repeatCount="indefinite" path={line} />
          </circle>
          <circle r="3.4" fill="#fff" style={{ filter: 'drop-shadow(0 0 5px var(--neg))' }}>
            <animateMotion dur="3.6s" repeatCount="indefinite" path={line} />
            <animate attributeName="r" values="3;4.2;3" dur="1.6s" repeatCount="indefinite" />
          </circle>
        </g>
      </svg>

      {/* x labels */}
      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 12px 0' }}>
        {data.labels.map((l, i) => (
          <span key={i} style={{ fontFamily: SF, fontSize: 11, fontWeight: 600, letterSpacing: 0.3,
            color: i === peakIdx ? 'var(--neg)' : 'var(--label3)' }}>{l}</span>
        ))}
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Spending-by-category — liquid bars, staggered rise, elastic press
// ════════════════════════════════════════════════════════════════════
function CategoryBars({ data, rangeKey }) {
  const total = data.cats.reduce((s, c) => s + c.amount, 0);
  const max = Math.max(...data.cats.map(c => c.amount));
  const [grown, setGrown] = aS(false);
  const [active, setActive] = aS(null);
  aE(() => {
    setGrown(false);
    const t = requestAnimationFrame(() => requestAnimationFrame(() => setGrown(true)));
    return () => cancelAnimationFrame(t);
  }, [rangeKey]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {data.cats.map((c, i) => {
        const meta = CAT[c.id] || CAT.other;
        const col = meta.color;
        const pct = (c.amount / max) * 100;
        const share = Math.round((c.amount / total) * 100);
        const on = active === c.id;
        return (
          <div key={c.id} style={{ position: 'relative' }}>
            {/* tooltip glass chip */}
            {on && (
              <div style={{ position: 'absolute', left: `min(${pct}%, calc(100% - 12px))`, bottom: 'calc(100% + 2px)', zIndex: 5,
                transform: 'translateX(-50%)', animation: 'lqaTipIn .42s cubic-bezier(.34,1.46,.44,1) both', pointerEvents: 'none' }}>
                <div style={{ position: 'relative', padding: '8px 13px', borderRadius: 14, whiteSpace: 'nowrap',
                  background: 'var(--glass-tint-strong)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)',
                  border: `0.5px solid color-mix(in srgb, ${col} 55%, transparent)`,
                  boxShadow: `var(--glass-shadow-float), 0 0 22px color-mix(in srgb, ${col} 30%, transparent)` }}>
                  <div style={{ fontFamily: SF, fontSize: 15, fontWeight: 700, letterSpacing: -0.4, color: '#fff' }}>{money(c.amount, false)}</div>
                  <div style={{ fontFamily: SF, fontSize: 11.5, fontWeight: 500, color: 'var(--label2)', marginTop: 1 }}>{share}% of spend</div>
                  <div style={{ position: 'absolute', left: '50%', top: '100%', transform: 'translateX(-50%)', width: 0, height: 0,
                    borderLeft: '6px solid transparent', borderRight: '6px solid transparent',
                    borderTop: `6px solid color-mix(in srgb, ${col} 22%, var(--bg))` }} />
                </div>
              </div>
            )}

            <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 7 }}>
              <span style={{ width: 22, height: 22, borderRadius: 7, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
                background: `color-mix(in srgb, ${col} 20%, transparent)`, boxShadow: `0 0 12px color-mix(in srgb, ${col} 38%, transparent)` }}>
                <Icon name={meta.icon} size={13} color={col} weight={2.4} />
              </span>
              <span style={{ flex: 1, fontFamily: SF, fontSize: 14, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.2 }}>{meta.name}</span>
              <span style={{ fontFamily: SF, fontSize: 13.5, fontWeight: 600, color: 'var(--label2)', fontVariantNumeric: 'tabular-nums' }}>{money(c.amount, false)}</span>
            </div>

            {/* track + liquid fill */}
            <button onPointerDown={() => setActive(on ? null : c.id)} className="lq-rippleable" style={{
              display: 'block', width: '100%', border: 'none', background: 'var(--fill3)', cursor: 'pointer',
              height: 14, borderRadius: 999, padding: 0, position: 'relative', overflow: 'visible' }}>
              <div style={{ position: 'absolute', inset: 0, borderRadius: 999, overflow: 'hidden' }}>
                <div style={{
                  position: 'absolute', left: 0, top: 0, bottom: 0, borderRadius: 999, overflow: 'hidden',
                  width: grown ? `${pct}%` : '0%',
                  transform: on ? 'scaleY(1.5)' : 'scaleY(1)', transformOrigin: 'center',
                  background: `linear-gradient(90deg, color-mix(in srgb, ${col} 55%, #000 6%), ${col})`,
                  boxShadow: `0 0 14px color-mix(in srgb, ${col} 60%, transparent), inset 0 1px 0 rgba(255,255,255,0.4)`,
                  transition: `width .8s cubic-bezier(.34,1.32,.42,1) ${i * 60}ms, transform .5s cubic-bezier(.34,1.7,.42,1)` }}>
                  {/* liquid shimmer */}
                  <div className="lqa-shimmer" style={{ position: 'absolute', top: 0, bottom: 0, width: '38%',
                    background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.45), transparent)',
                    animation: `lqaShimmer ${3.4 + i * 0.3}s ease-in-out ${i * 0.4}s infinite` }} />
                </div>
              </div>
            </button>
          </div>
        );
      })}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// AI Insight card — frosted glass, violet edge, typewriter, breathing orb
// ════════════════════════════════════════════════════════════════════
function AIInsight({ text, rangeKey }) {
  const [shown, setShown] = aS('');
  aE(() => {
    setShown('');
    let i = 0; let raf;
    const start = performance.now();
    const speed = 22; // chars per second feel via interval
    const id = setInterval(() => {
      i += 1;
      setShown(text.slice(0, i));
      if (i >= text.length) clearInterval(id);
    }, 26);
    return () => clearInterval(id);
  }, [rangeKey, text]);
  const typing = shown.length < text.length;

  return (
    <div style={{ position: 'relative', margin: '0 16px', borderRadius: 22, overflow: 'hidden', isolation: 'isolate',
      background: 'var(--glass-tint-strong)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)',
      border: 'var(--glass-border)', boxShadow: 'var(--glass-shadow)' }}>
      {/* glowing violet left border */}
      <div className="lqa-edgeglow" style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 4,
        background: 'linear-gradient(180deg, #C4A6FF, #7C5CFF)',
        boxShadow: '0 0 16px 1px #8B5CF6, 0 0 30px 3px color-mix(in srgb, #8B5CF6 50%, transparent)',
        animation: 'lqaEdgeGlow 3.2s ease-in-out infinite' }} />
      {/* violet wash */}
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(120% 90% at 0% 0%, color-mix(in srgb, #8B5CF6 16%, transparent), transparent 58%)' }} />

      <div style={{ position: 'relative', padding: '18px 20px 20px 22px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Icon name="sparkles" size={16} color="#C4A6FF" />
            <span style={{ fontFamily: SF, fontSize: 12, fontWeight: 700, letterSpacing: 1.2, textTransform: 'uppercase', color: '#C4A6FF' }}>AI Insight</span>
          </div>
          {/* breathing AI orb */}
          <span style={{ position: 'relative', width: 14, height: 14, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <span className="lqa-orbring" style={{ position: 'absolute', width: 14, height: 14, borderRadius: '50%',
              border: '1.5px solid var(--glow)', animation: 'lqaOrbRing 2.4s ease-out infinite' }} />
            <span className="lqa-orb" style={{ width: 11, height: 11, borderRadius: '50%',
              background: 'radial-gradient(circle at 35% 30%, #fff, var(--glow) 70%)',
              animation: 'lqaOrbBreathe 2.4s ease-in-out infinite' }} />
          </span>
        </div>
        <div style={{ fontFamily: SF, fontSize: 15.5, lineHeight: 1.5, fontWeight: 500, color: 'var(--label)', letterSpacing: -0.2, minHeight: 70, textWrap: 'pretty' }}>
          {shown}
          <span style={{ display: 'inline-block', width: 2, height: '1.05em', verticalAlign: '-0.16em', marginLeft: 1,
            background: '#C4A6FF', opacity: typing ? 1 : 0,
            animation: typing ? 'none' : 'lqaCaret 1s step-end infinite', borderRadius: 1 }} />
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Screen
// ════════════════════════════════════════════════════════════════════
function Analytics({ palette, onClose, plasma = true }) {
  const [range, setRange] = aS('Month');
  const [scrollY, setScrollY] = aS(0);
  const data = SERIES[range];

  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
      {plasma
        ? <ParallaxAmbient palette={palette} scrollY={scrollY} />
        : <div style={{ position: 'absolute', inset: 0, background: 'var(--bg)', zIndex: 0 }}>
            <div style={{ position: 'absolute', inset: 0, background: 'var(--ambient)', pointerEvents: 'none' }} />
          </div>}
      <div className="noscroll" onScroll={e => setScrollY(e.currentTarget.scrollTop)}
        style={{ position: 'absolute', inset: 0, overflowY: 'auto', overflowX: 'hidden', zIndex: 1 }}>
        <div style={{ paddingTop: 64, paddingBottom: 54 }}>
          {/* header */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 18px 18px' }}>
            {onClose && <GlassCircle name="chevron.left" iconSize={20} onClick={onClose} />}
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', fontWeight: 500 }}>Spending overview</div>
              <div style={{ fontFamily: SF, fontSize: 22, fontWeight: 700, letterSpacing: -0.5, color: 'var(--label)' }}>Analytics</div>
            </div>
            <GlassCircle name="slider" iconSize={19} />
          </div>

          {/* time-range tabs */}
          <LiquidTabs ranges={RANGES} active={range} onChange={setRange} />

          {/* total spend headline */}
          <div style={{ padding: '22px 20px 4px' }}>
            <div style={{ fontFamily: SF, fontSize: 12, fontWeight: 600, letterSpacing: 1.4, color: 'var(--label2)', textTransform: 'uppercase' }}>Total spend</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginTop: 6 }}>
              <RollingMoney value={data.total} cents={false} animateOnMount style={{ fontFamily: SF, fontSize: 42, fontWeight: 300, letterSpacing: -1.5, lineHeight: 1.15,
                color: 'var(--label)', textShadow: '0 0 26px color-mix(in srgb, var(--neg) 30%, transparent)' }} />
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '4px 9px', borderRadius: 20,
                background: `color-mix(in srgb, ${data.deltaPct <= 0 ? 'var(--pos)' : 'var(--neg)'} 13%, transparent)`,
                border: `0.5px solid color-mix(in srgb, ${data.deltaPct <= 0 ? 'var(--pos)' : 'var(--neg)'} 38%, transparent)` }}>
                <Icon name={data.deltaPct <= 0 ? 'arrow.down' : 'arrow.up'} size={11} color={data.deltaPct <= 0 ? 'var(--pos)' : 'var(--neg)'} weight={2.8} />
                <span style={{ fontFamily: SF, fontSize: 12, fontWeight: 700, color: data.deltaPct <= 0 ? 'var(--pos)' : 'var(--neg)' }}>{Math.abs(data.deltaPct)}%</span>
              </span>
            </div>
            <div style={{ fontFamily: SF, fontSize: 12.5, color: 'var(--label3)', marginTop: 3 }}>{data.vs}</div>
          </div>

          {/* hero area chart card */}
          <div style={{ margin: '16px 16px 0', position: 'relative', borderRadius: 28, padding: '20px 14px 16px', overflow: 'hidden', isolation: 'isolate',
            background: 'var(--glass-tint-strong)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)',
            border: 'var(--glass-border)', boxShadow: 'var(--glass-shadow-float)' }}>
            <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none',
              background: 'linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0) 30%)' }} />
            <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 6px 6px' }}>
              <span style={{ fontFamily: SF, fontSize: 13, fontWeight: 600, letterSpacing: 0.3, color: 'var(--label)' }}>Spending trend</span>
              <span style={{ fontFamily: SF, fontSize: 12, color: 'var(--label2)' }}>{range === 'Year' ? '2026' : range === 'Month' ? 'June 2026' : 'This week'}</span>
            </div>
            <AreaChart key={range} data={data} rangeKey={range} />
          </div>

          {/* AI insight */}
          <div style={{ marginTop: 18 }}>
            <AIInsight key={range} text={data.insight} rangeKey={range} />
          </div>

          {/* spending by category */}
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', padding: '28px 20px 16px' }}>
            <div style={{ fontFamily: SF, fontSize: 20, fontWeight: 700, letterSpacing: -0.4, color: 'var(--label)' }}>By category</div>
            <span style={{ fontFamily: SF, fontSize: 12.5, color: 'var(--label3)' }}>tap a bar</span>
          </div>
          <div style={{ padding: '0 20px' }}>
            <CategoryBars key={range} data={data} rangeKey={range} />
          </div>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Slide-in wrapper — pushed over the app from the Overview button
// ════════════════════════════════════════════════════════════════════
function AnalyticsScreen({ open, onClose, palette, plasma = true }) {
  if (!open) return null;
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 50, background: 'var(--bg)', overflow: 'hidden' }}>
      <Analytics palette={palette} plasma={plasma} onClose={onClose} />
    </div>
  );
}

Object.assign(window, { Analytics, AnalyticsScreen, SERIES, RANGES });
