// charts.jsx — neon-glow donut ring + animated category breakdown. Pure SVG.

function Donut({ segments, size = 150, thickness = 22, gap = 0.014, center, glow = true }) {
  const total = segments.reduce((s, x) => s + x.value, 0) || 1;
  const r = (size - thickness) / 2;
  const C = 2 * Math.PI * r;
  let offset = 0;
  const [grown, setGrown] = React.useState(false);
  React.useEffect(() => { const t = setTimeout(() => setGrown(true), 80); return () => clearTimeout(t); }, []);
  return (
    <div style={{ position: 'relative', width: size, height: size, flexShrink: 0 }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)', overflow: 'visible' }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--fill3)" strokeWidth={thickness} />
        {segments.map((s, i) => {
          const frac = s.value / total;
          const len = grown ? Math.max(frac - gap, 0) * C : 0;
          const dash = `${len} ${C - len}`;
          const el = (
            <circle key={i} cx={size / 2} cy={size / 2} r={r} fill="none" stroke={s.color}
              strokeWidth={thickness} strokeDasharray={dash} strokeDashoffset={-offset * C}
              strokeLinecap="round"
              style={{ transition: 'stroke-dasharray .9s cubic-bezier(.34,1.32,.42,1)',
                filter: glow && s.color !== 'transparent' ? `drop-shadow(0 0 5px ${s.color}) drop-shadow(0 0 1px ${s.color})` : 'none' }} />
          );
          offset += frac;
          return el;
        })}
      </svg>
      {center && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>{center}</div>
      )}
    </div>
  );
}

// Horizontal stacked breakdown bar
function StackBar({ segments, height = 12 }) {
  const total = segments.reduce((s, x) => s + x.value, 0) || 1;
  const [grown, setGrown] = React.useState(false);
  React.useEffect(() => { const t = setTimeout(() => setGrown(true), 80); return () => clearTimeout(t); }, []);
  return (
    <div style={{ display: 'flex', gap: 2, height, width: '100%' }}>
      {segments.map((s, i) => (
        <div key={i} style={{ width: grown ? `${(s.value / total) * 100}%` : '0%', background: s.color,
          borderRadius: 3, boxShadow: `0 0 6px ${s.color}`,
          transition: 'width .7s cubic-bezier(.34,1.32,.42,1)', transitionDelay: `${i * 30}ms` }} />
      ))}
    </div>
  );
}

Object.assign(window, { Donut, StackBar });
