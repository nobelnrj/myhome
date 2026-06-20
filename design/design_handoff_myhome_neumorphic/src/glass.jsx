// glass.jsx — iOS 26 Liquid Glass material primitives.
// A surface = backdrop blur + translucent tint + specular rim + soft float shadow.

function Glass({ radius = 22, tint = 'var(--glass-tint)', float = false, border = true,
  sheen = false, style = {}, children, className, onClick }) {
  return (
    <div className={className} onClick={onClick} style={{
      position: 'relative', borderRadius: radius, isolation: 'isolate',
      boxShadow: float ? 'var(--glass-shadow-float)' : 'var(--glass-shadow)', ...style,
    }}>
      {/* blur + tint */}
      <div style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: tint,
        backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)' }} />
      {/* specular rim + hairline border */}
      {border && <div style={{ position: 'absolute', inset: 0, borderRadius: 'inherit',
        boxShadow: 'var(--glass-rim)', border: 'var(--glass-border)', pointerEvents: 'none' }} />}
      {/* diagonal light streak */}
      {sheen && <div style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', pointerEvents: 'none',
        background: 'linear-gradient(152deg, rgba(255,255,255,0.4) 0%, rgba(255,255,255,0) 38%)' }} />}
      <div style={{ position: 'relative', zIndex: 1, borderRadius: 'inherit' }}>{children}</div>
    </div>
  );
}

// Circular glass nav button (bell / +) — floats over scrolling content.
function GlassCircle({ name, onClick, size = 38, iconSize = 21, color = 'var(--accent)', fill = false }) {
  return (
    <button className="tap" onClick={onClick} style={{
      width: size, height: size, borderRadius: '50%', border: 'none', cursor: 'pointer', padding: 0,
      position: 'relative', background: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: 'var(--glass-shadow)', isolation: 'isolate',
    }}>
      <span style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: 'var(--glass-tint-strong)',
        backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)' }} />
      <span style={{ position: 'absolute', inset: 0, borderRadius: '50%', boxShadow: 'var(--glass-rim)',
        border: 'var(--glass-border)', pointerEvents: 'none' }} />
      <Icon name={name} size={iconSize} color={color} weight={2.2} fill={fill} style={{ position: 'relative', zIndex: 1 }} />
    </button>
  );
}

Object.assign(window, { Glass, GlassCircle });
