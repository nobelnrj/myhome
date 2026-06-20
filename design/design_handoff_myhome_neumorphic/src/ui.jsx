// ui.jsx — strict-iOS primitives: Screen (collapsing large title), grouped
// lists & rows, nav buttons, tab bar, sheet, segmented control, search, switch.
const { useState, useRef, useEffect } = React;

const STATUS_H = 59;
const NAV_H = 44;
const TABBAR_H = 100; // clearance for the floating glass capsule

function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

// ── Screen: status-bar clearance + collapsing large title + chrome hairline ──
function Screen({ title, large = true, left, right, children, contentStyle = {} }) {
  const [st, setSt] = useState(0);
  const showChrome = st > 6;
  const inlineOp = large ? clamp((st - 22) / 26, 0, 1) : 1;
  return (
    <div style={{ position: 'absolute', inset: 0, background: 'var(--bg-grouped)', overflow: 'hidden' }}>
      {/* ambient color field so glass chrome has something to refract */}
      <div style={{ position: 'absolute', inset: 0, background: 'var(--ambient)', pointerEvents: 'none' }} />
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, zIndex: 30, paddingTop: STATUS_H,
        background: showChrome ? 'var(--chrome)' : 'transparent',
        backdropFilter: showChrome ? 'var(--chrome-blur)' : 'none',
        WebkitBackdropFilter: showChrome ? 'var(--chrome-blur)' : 'none',
        borderBottom: `0.5px solid ${showChrome ? 'var(--sep)' : 'transparent'}`,
        transition: 'background .25s ease, border-color .25s ease',
      }}>
        <div style={{ height: NAV_H, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 8px' }}>
          <div style={{ minWidth: 72, display: 'flex', alignItems: 'center', gap: 2 }}>{left}</div>
          <div style={{ flex: 1, textAlign: 'center', fontFamily: SF, fontSize: 17, fontWeight: 600,
            letterSpacing: -0.4, color: 'var(--label)', opacity: inlineOp, textShadow: '0 1px 14px rgba(0,0,0,0.3)',
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
          <div style={{ minWidth: 72, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 4 }}>{right}</div>
        </div>
      </div>
      <div className="noscroll" onScroll={e => setSt(e.target.scrollTop)} style={{
        position: 'absolute', inset: 0, overflowY: 'auto', overflowX: 'hidden',
        paddingTop: STATUS_H + NAV_H, paddingBottom: TABBAR_H + 8, ...contentStyle,
      }}>
        {large && (
          <h1 style={{ margin: 0, padding: '2px 16px 8px', fontFamily: SF, fontSize: 34, fontWeight: 700,
            letterSpacing: 0.37, color: 'var(--label)', lineHeight: 1.1, textShadow: '0 2px 18px rgba(0,0,0,0.32)' }}>{title}</h1>
        )}
        {children}
      </div>
    </div>
  );
}

// Nav-bar text/icon button (accent)
function NavButton({ children, onClick, prominent = false, color = 'var(--accent)', disabled = false }) {
  return (
    <button className="tap" onClick={disabled ? undefined : onClick} style={{
      border: 'none', background: 'none', cursor: disabled ? 'default' : 'pointer',
      fontFamily: SF, fontSize: 17, fontWeight: prominent ? 600 : 400,
      color: disabled ? 'var(--label3)' : color, padding: '6px 8px', display: 'flex',
      alignItems: 'center', gap: 4, opacity: disabled ? 0.6 : 1,
    }}>{children}</button>
  );
}

// Circular liquid-glass nav action (e.g. + / bell) — floats over content.
function NavIconButton({ name, onClick, color = 'var(--accent)' }) {
  return <GlassCircle name={name} onClick={onClick} color={color} size={38} iconSize={21} />;
}

// Rounded-square category/icon tile
function IconTile({ icon, color, size = 30, iconColor = '#fff', radius }) {
  return (
    <div style={{ width: size, height: size, borderRadius: radius != null ? radius : size * 0.28,
      background: color, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      <Icon name={icon} size={size * 0.62} color={iconColor} weight={2.1} />
    </div>
  );
}

// ── Grouped list ──
function GroupedList({ header, footer, children, style = {} }) {
  const kids = React.Children.toArray(children).filter(Boolean);
  return (
    <div style={{ margin: '0 0 22px', ...style }}>
      {header && <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)',
        padding: '0 32px 7px', letterSpacing: -0.08, textTransform: 'uppercase' }}>{header}</div>}
      <div className="lq-num" style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', margin: '0 16px',
        overflow: 'hidden', boxShadow: 'var(--card-shadow)' }}>
        {kids.map((c, i) => typeof c.type === 'string' ? c : React.cloneElement(c, { isLast: i === kids.length - 1 }))}
      </div>
      {footer && <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)',
        padding: '7px 32px 0', letterSpacing: -0.08, lineHeight: 1.35 }}>{footer}</div>}
    </div>
  );
}

// ── List row ──
function Row({ icon, iconNode, title, titleColor, subtitle, value, valueColor, valueBold,
  accessory = 'chevron', onClick, isLast, height = 44, leftInset, children }) {
  const insetL = leftInset != null ? leftInset : (icon || iconNode ? 60 : 16);
  return (
    <div className={onClick ? 'rowtap' : ''} onClick={onClick} style={{
      position: 'relative', display: 'flex', alignItems: 'center', gap: 12,
      minHeight: height, padding: '7px 16px', cursor: onClick ? 'pointer' : 'default',
      background: 'var(--bg-elevated)',
    }}>
      {iconNode || (icon && <IconTile {...icon} />)}
      <div style={{ flex: 1, minWidth: 0 }}>
        {children || (
          <>
            <div style={{ fontFamily: SF, fontSize: 17, letterSpacing: -0.4,
              color: titleColor || 'var(--label)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
            {subtitle && <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)',
              marginTop: 1, letterSpacing: -0.08, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{subtitle}</div>}
          </>
        )}
      </div>
      {value != null && <div style={{ fontFamily: SF, fontSize: 17, letterSpacing: -0.4,
        color: valueColor || 'var(--label2)', fontWeight: valueBold ? 600 : 400, flexShrink: 0 }}>{value}</div>}
      {accessory === 'chevron' && <Icon name="chevron.right" size={16} color="var(--label3)" weight={2.5} />}
      {accessory === 'detail' && <Icon name="chevron.right" size={16} color="var(--label3)" weight={2.5} />}
      {typeof accessory === 'object' && accessory}
      {!isLast && <div style={{ position: 'absolute', left: insetL, right: 0, bottom: 0, height: 0.5, background: 'var(--sep)' }} />}
    </div>
  );
}

// ── iOS switch (neon glow when on) ──
function Toggle({ value, onChange }) {
  return (
    <button onClick={() => onChange(!value)} style={{
      width: 51, height: 31, borderRadius: 31, border: 'none', cursor: 'pointer', padding: 0,
      background: value ? 'var(--green)' : 'var(--fill)', position: 'relative',
      boxShadow: value ? '0 0 14px color-mix(in srgb, var(--green) 65%, transparent), inset 0 0 0 0.5px rgba(255,255,255,0.2)' : 'inset 0 0 0 0.5px rgba(255,255,255,0.08)',
      transition: `background .25s, box-shadow .25s`, flexShrink: 0,
    }}>
      <span style={{ position: 'absolute', top: 2, left: value ? 22 : 2, width: 27, height: 27,
        borderRadius: '50%', background: '#fff', boxShadow: '0 3px 8px rgba(0,0,0,0.28), 0 1px 1px rgba(0,0,0,0.2)',
        transition: `left .3s ${SPRING}` }} />
    </button>
  );
}

// ── segmented control ──
function Segmented({ options, value, onChange }) {
  const i = options.findIndex(o => (o.id ?? o) === value);
  return (
    <div style={{ display: 'flex', background: 'var(--fill3)', borderRadius: 9, padding: 2, position: 'relative' }}>
      <div style={{ position: 'absolute', top: 2, bottom: 2, left: `calc(${(100 / options.length) * Math.max(i, 0)}% + 2px)`,
        width: `calc(${100 / options.length}% - 4px)`, background: 'var(--bg-elevated2)', borderRadius: 7,
        border: '0.5px solid rgba(255,255,255,0.10)',
        boxShadow: '0 2px 8px rgba(0,0,0,0.22), inset 0 1px 0 rgba(255,255,255,0.12)', transition: `left .26s ${SPRING}` }} />
      {options.map((o, k) => {
        const id = o.id ?? o, label = o.label ?? o;
        return (
          <button key={id} onClick={() => onChange(id)} style={{ flex: 1, zIndex: 1, border: 'none', background: 'none',
            cursor: 'pointer', fontFamily: SF, fontSize: 13, fontWeight: id === value ? 600 : 500,
            color: 'var(--label)', padding: '6px 4px', letterSpacing: -0.08 }}>{label}</button>
        );
      })}
    </div>
  );
}

// ── search bar ──
function SearchBar({ value, onChange, placeholder = 'Search' }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, background: 'var(--fill3)', borderRadius: 10,
      padding: '8px 10px', margin: '0 16px 12px' }}>
      <Icon name="magnifyingglass" size={17} color="var(--label2)" weight={2.4} />
      <input value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} style={{
        flex: 1, border: 'none', background: 'none', outline: 'none', fontFamily: SF, fontSize: 17,
        letterSpacing: -0.4, color: 'var(--label)' }} />
      {value && <button className="tap" onClick={() => onChange('')} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
        <Icon name="xmark.circle.fill" size={18} /></button>}
    </div>
  );
}

// ── progress bar (Budgets) ──
function ProgressBar({ frac, color, height = 8 }) {
  const f = clamp(frac, 0, 1);
  return (
    <div style={{ height, borderRadius: height, background: 'var(--fill3)', overflow: 'hidden', width: '100%' }}>
      <div style={{ height: '100%', width: `${f * 100}%`, background: color, borderRadius: height, boxShadow: `0 0 8px ${color}`, transition: `width .6s ${SPRING}` }} />
    </div>
  );
}

// ── floating liquid-glass tab bar (iOS 26 capsule) ──
function TabBar({ tabs, active, onChange }) {
  const i = Math.max(0, tabs.findIndex(t => t.id === active));
  const n = tabs.length;
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, bottom: 24, zIndex: 40,
      display: 'flex', justifyContent: 'center', pointerEvents: 'none' }}>
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center', height: 62, padding: '0 8px',
        borderRadius: 34, pointerEvents: 'auto', boxShadow: 'var(--glass-shadow-float)', isolation: 'isolate' }}>
        {/* glass body */}
        <div style={{ position: 'absolute', inset: 0, borderRadius: 34, background: 'var(--glass-tint-strong)',
          backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)' }} />
        <div style={{ position: 'absolute', inset: 0, borderRadius: 34, boxShadow: 'var(--glass-rim)',
          border: 'var(--glass-border)', pointerEvents: 'none' }} />
        {/* sliding active highlight */}
        <div style={{ position: 'absolute', top: 6, bottom: 6, width: 58,
          left: 8 + i * 58, borderRadius: 26, background: 'var(--accent-soft)',
          boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, var(--accent) 35%, transparent), 0 0 16px color-mix(in srgb, var(--accent) 22%, transparent)',
          transition: `left .4s ${SPRING}` }} />
        {tabs.map(t => {
          const on = t.id === active;
          return (
            <button key={t.id} className="tap" onClick={() => onChange(t.id)} style={{ position: 'relative', zIndex: 1,
              width: 58, border: 'none', background: 'none', cursor: 'pointer', display: 'flex', flexDirection: 'column',
              alignItems: 'center', gap: 3, padding: '7px 0' }}>
              <Icon name={t.icon} size={24} fill={on} color={on ? 'var(--accent)' : 'var(--label2)'} weight={2}
                style={{ filter: on ? 'drop-shadow(0 0 7px var(--accent))' : 'none', transition: 'filter .3s' }} />
              <span style={{ fontFamily: SF, fontSize: 10, fontWeight: on ? 600 : 500, letterSpacing: 0,
                color: on ? 'var(--accent)' : 'var(--label2)' }}>{t.label}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ── modal sheet (slides up, dims behind) ──
function Sheet({ open, onClose, title, left, right, children, full = false }) {
  const [mounted, setMounted] = useState(open);
  const [shown, setShown] = useState(false);
  useEffect(() => {
    if (open) { setMounted(true); requestAnimationFrame(() => requestAnimationFrame(() => setShown(true))); }
    else { setShown(false); const t = setTimeout(() => setMounted(false), 320); return () => clearTimeout(t); }
  }, [open]);
  if (!mounted) return null;
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 60 }}>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.4)',
        opacity: shown ? 1 : 0, transition: 'opacity .3s' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0,
        top: full ? 12 : 54, background: 'var(--chrome)', backdropFilter: 'var(--chrome-blur)', WebkitBackdropFilter: 'var(--chrome-blur)', borderRadius: '20px 20px 0 0',
        border: 'var(--glass-border)', borderBottom: 'none',
        transform: shown ? 'translateY(0)' : 'translateY(100%)',
        transition: 'transform .34s cubic-bezier(.32,.72,0,1)', overflow: 'hidden',
        display: 'flex', flexDirection: 'column', boxShadow: '0 -1px 0 rgba(0,0,0,0.04)' }}>
        <div style={{ height: 56, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '0 12px', flexShrink: 0, position: 'relative' }}>
          <div style={{ minWidth: 70, display: 'flex' }}>{left}</div>
          <div style={{ flex: 1, textAlign: 'center', fontFamily: SF, fontSize: 17, fontWeight: 600,
            color: 'var(--label)', letterSpacing: -0.4 }}>{title}</div>
          <div style={{ minWidth: 70, display: 'flex', justifyContent: 'flex-end' }}>{right}</div>
          <div style={{ position: 'absolute', top: 5, left: '50%', transform: 'translateX(-50%)',
            width: 36, height: 5, borderRadius: 5, background: 'var(--fill)' }} />
        </div>
        <div className="noscroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>{children}</div>
      </div>
    </div>
  );
}

// ── pushed screen (NavigationStack push: slides from right, over the tab bar) ──
function PushView({ open, onClose, title, right, children, contentStyle = {} }) {
  const [mounted, setMounted] = useState(open);
  const [shown, setShown] = useState(false);
  useEffect(() => {
    if (open) { setMounted(true); requestAnimationFrame(() => requestAnimationFrame(() => setShown(true))); }
    else { setShown(false); const t = setTimeout(() => setMounted(false), 320); return () => clearTimeout(t); }
  }, [open]);
  const [st, setSt] = useState(0);
  if (!mounted) return null;
  const showChrome = st > 6;
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 50, background: 'var(--bg)',
      transform: shown ? 'translateX(0)' : 'translateX(100%)',
      transition: `transform .4s ${SPRING_SOFT}`, overflow: 'hidden',
      boxShadow: shown ? '-12px 0 32px rgba(0,0,0,0.4)' : 'none' }}>
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(110% 60% at 10% 0%, color-mix(in srgb, var(--accent) 14%, transparent), transparent 60%), radial-gradient(110% 60% at 100% 100%, color-mix(in srgb, var(--neg) 12%, transparent), transparent 60%)' }} />
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 30, paddingTop: STATUS_H,
        background: showChrome ? 'var(--chrome)' : 'transparent', backdropFilter: showChrome ? 'var(--chrome-blur)' : 'none',
        WebkitBackdropFilter: showChrome ? 'var(--chrome-blur)' : 'none',
        borderBottom: `0.5px solid ${showChrome ? 'var(--sep)' : 'transparent'}`, transition: 'background .25s, border-color .25s' }}>
        <div style={{ height: NAV_H, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 8px' }}>
          <div style={{ minWidth: 90, display: 'flex' }}><NavButton onClick={onClose}><Icon name="chevron.left" size={22} color="var(--accent)" weight={2.4} />Back</NavButton></div>
          <div style={{ flex: 1, textAlign: 'center', fontFamily: SF, fontSize: 17, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.4, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
          <div style={{ minWidth: 90, display: 'flex', justifyContent: 'flex-end' }}>{right}</div>
        </div>
      </div>
      <div className="noscroll" onScroll={e => setSt(e.target.scrollTop)} style={{ position: 'absolute', inset: 0, overflowY: 'auto', overflowX: 'hidden',
        paddingTop: STATUS_H + NAV_H + 8, paddingBottom: 24, ...contentStyle }}>{children}</div>
    </div>
  );
}

Object.assign(window, {
  Screen, NavButton, NavIconButton, IconTile, GroupedList, Row, Toggle,
  Segmented, SearchBar, ProgressBar, TabBar, Sheet, PushView, clamp,
  STATUS_H, NAV_H, TABBAR_H,
});
