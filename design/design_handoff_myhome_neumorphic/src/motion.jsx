// motion.jsx — Liquid UI motion system.
//   PlasmaField  : void canvas with slowly-morphing, breathing plasma blobs.
//   RollingNumber/RollingMoney : spring-eased odometer count on value change.
//   installRipple: global "press water" ripple on interactive surfaces.

const { useState: _uS, useRef: _uR, useEffect: _uE, useContext: _uC, createContext: _cC } = React;

// Context: whether monetary values roll on change (Tweak-controlled).
const RollCtx = _cC(true);

function RollingNumber({ value, format, duration = 780, enabled, animateOnMount = false, style, className }) {
  const ctxEnabled = _uC(RollCtx);
  const on = enabled !== undefined ? enabled : ctxEnabled;
  const fmt = format || ((n) => String(Math.round(n)));
  const [disp, setDisp] = _uS(animateOnMount && on ? 0 : value);
  const fromRef = _uR(animateOnMount && on ? 0 : value);
  const raf = _uR(0);

  _uE(() => {
    if (!on) { cancelAnimationFrame(raf.current); setDisp(value); fromRef.current = value; return; }
    const from = fromRef.current, to = value;
    if (from === to) { setDisp(to); return; }
    const t0 = performance.now();
    const ease = (x) => 1 - Math.pow(1 - x, 3); // easeOutCubic
    cancelAnimationFrame(raf.current);
    const tick = (now) => {
      const p = Math.min((now - t0) / duration, 1);
      setDisp(from + (to - from) * ease(p));
      if (p < 1) raf.current = requestAnimationFrame(tick);
      else fromRef.current = to;
    };
    raf.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf.current);
  }, [value, on, duration]);

  return <span className={'lq-num' + (className ? ' ' + className : '')} style={style}>{fmt(disp)}</span>;
}

function RollingMoney({ value, cents = false, signed = false, ...rest }) {
  const fmt = (n) => {
    if (signed) { const s = n >= 0 ? '+' : '-'; return s + money(Math.abs(n), cents).replace('-', ''); }
    return money(n, cents);
  };
  return <RollingNumber value={value} format={fmt} {...rest} />;
}

// ── Plasma field ──
const INTENSITY = {
  calm:     { mult: 1.9, op: 0.46, blur: 78 },
  balanced: { mult: 1.3, op: 0.52, blur: 70 },
  alive:    { mult: 0.82, op: 0.58, blur: 62 },
};

function PlasmaField({ palette = ['#003D2E', '#1A0533', '#02414F'], intensity = 'alive', theme = 'void' }) {
  const cfg = INTENSITY[intensity] || INTENSITY.alive;
  const frosted = theme === 'frosted';
  // frosted: soften deep hues to pastel washes, blend by multiply on the light canvas
  const tint = (hex) => frosted ? `color-mix(in srgb, ${hex} 34%, #ffffff)` : hex;
  const blend = frosted ? 'multiply' : 'screen';
  const op = frosted ? cfg.op * 0.85 : cfg.op;

  const blobs = [
    { c: palette[0], w: 460, h: 460, left: '-22%', top: '-12%', anim: 'lqDrift1', dur: 13 * cfg.mult },
    { c: palette[1], w: 520, h: 520, left: '34%',  top: '46%',  anim: 'lqDrift2', dur: 17 * cfg.mult },
    { c: palette[2], w: 400, h: 400, left: '48%',  top: '-8%',  anim: 'lqDrift3', dur: 15 * cfg.mult },
  ];
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: 'var(--bg)', pointerEvents: 'none', zIndex: 0 }}>
      {blobs.map((b, i) => (
        <div key={i} className="lq-blob" style={{
          width: b.w, height: b.h, left: b.left, top: b.top,
          background: `radial-gradient(circle at 50% 50%, ${tint(b.c)} 0%, ${tint(b.c)} 24%, transparent 70%)`,
          filter: `blur(${cfg.blur}px)`, opacity: op, mixBlendMode: blend,
          animation: `${b.anim} ${b.dur}s ease-in-out infinite`,
        }} />
      ))}
      {/* gentle scrim tames peak blob brightness so text stays legible */}
      <div style={{ position: 'absolute', inset: 0, background: frosted ? 'rgba(234,238,246,0.18)' : 'rgba(5,6,15,0.24)' }} />
      <div style={{ position: 'absolute', inset: 0, background: frosted ? 'none' : 'radial-gradient(130% 80% at 50% 120%, rgba(0,0,0,0.35), transparent 55%)' }} />
    </div>
  );
}

// ── Global water ripple ──
function installRipple() {
  if (window.__lqRippleInstalled) return;
  window.__lqRippleInstalled = true;
  document.addEventListener('pointerdown', (e) => {
    const el = e.target.closest && e.target.closest('.tap,.rowtap,.keycap,.lq-rippleable');
    if (!el || el.getAttribute('aria-disabled') === 'true') return;
    const r = el.getBoundingClientRect();
    if (r.width < 10 || r.height < 10) return;
    const s = (r.width / el.offsetWidth) || 1;
    const sp = document.createElement('span');
    sp.className = 'lq-ripple';
    const size = Math.max(el.offsetWidth, el.offsetHeight) * 2.1;
    sp.style.width = sp.style.height = size + 'px';
    sp.style.left = ((e.clientX - r.left) / s) + 'px';
    sp.style.top = ((e.clientY - r.top) / s) + 'px';
    el.appendChild(sp);
    setTimeout(() => sp.remove(), 700);
  }, true);
}

Object.assign(window, { RollCtx, RollingNumber, RollingMoney, PlasmaField, installRipple });
