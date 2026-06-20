// calendar.jsx — shared graphical month calendar (iOS .datePickerStyle(.graphical)).
const { useState: useStateCal } = React;

function MonthCalendar({ value, onSelect, events = {}, accent = 'var(--accent)', compact = false }) {
  // value: 'YYYY-MM-DD'
  const init = value ? value.split('-').map(Number) : [2026, 6, 3];
  const [view, setView] = useStateCal({ y: init[0], m: init[1] - 1 }); // m 0-indexed
  const key = (d) => `${view.y}-${String(view.m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  const first = new Date(view.y, view.m, 1).getDay();
  const daysIn = new Date(view.y, view.m + 1, 0).getDate();
  const cells = [];
  for (let i = 0; i < first; i++) cells.push(null);
  for (let d = 1; d <= daysIn; d++) cells.push(d);
  const dow = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  const monthName = new Date(view.y, view.m, 1).toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
  const shift = (n) => setView(v => { const d = new Date(v.y, v.m + n, 1); return { y: d.getFullYear(), m: d.getMonth() }; });
  const cell = compact ? 38 : 40;

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8, padding: '0 4px' }}>
        <div style={{ fontFamily: SF, fontSize: 17, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.4 }}>{monthName}</div>
        <div style={{ display: 'flex', gap: 18 }}>
          <button className="tap" onClick={() => shift(-1)} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4, display: 'flex' }}><Icon name="chevron.left" size={18} color={accent} weight={2.6} /></button>
          <button className="tap" onClick={() => shift(1)} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4, display: 'flex' }}><Icon name="chevron.right" size={18} color={accent} weight={2.6} /></button>
        </div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', marginBottom: 2 }}>
        {dow.map((d, i) => <div key={i} style={{ textAlign: 'center', fontFamily: SF, fontSize: 12, fontWeight: 600, color: 'var(--label3)', height: 22 }}>{d}</div>)}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)' }}>
        {cells.map((d, i) => {
          if (d == null) return <div key={i} style={{ height: cell }} />;
          const k = key(d); const ev = events[k]; const isSel = k === value; const isToday = k === TODAY;
          return (
            <button key={i} className="tap" onClick={() => onSelect && onSelect(k)} style={{ height: cell, border: 'none', background: 'none', cursor: 'pointer',
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2 }}>
              <span style={{ width: 33, height: 33, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontFamily: SF, fontSize: 17, fontWeight: isToday || isSel ? 600 : 400,
                background: isSel ? accent : 'transparent',
                color: isSel ? '#fff' : isToday ? accent : 'var(--label)' }}>{d}</span>
              <span style={{ height: 5, display: 'flex', gap: 2 }}>
                {(ev || []).slice(0, 3).map((e, j) => <span key={j} style={{ width: 5, height: 5, borderRadius: '50%', background: isSel ? '#fff' : e.color }} />)}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

Object.assign(window, { MonthCalendar });
