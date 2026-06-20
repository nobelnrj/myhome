// expenses.jsx — Activity: unified income + expense stream (grouped by day) + Gmail Review Inbox.
function relDay(d) {
  const today = new Date('2026-06-03T00:00');
  const dt = new Date(d + 'T00:00');
  const diff = Math.round((today - dt) / 86400000);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Yesterday';
  return dt.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
}
const catOf = (e) => (e.type === 'income' ? INCOME_CAT : CAT)[e.cat];

function ExpensesScreen({ ctx }) {
  const { expenses, income, review, nav, openExpense, openAdd, confirmReview, dismissReview,
    expenseSub, setExpenseSub } = ctx;
  const [q, setQ] = useState('');
  const sub = expenseSub;

  const activity = [...expenses, ...income].sort((a, b) => b.date.localeCompare(a.date) || a.merchant.localeCompare(b.merchant));
  const filtered = activity.filter(e => !q || e.merchant.toLowerCase().includes(q.toLowerCase()) || catOf(e).name.toLowerCase().includes(q.toLowerCase()));
  // group by date
  const groups = [];
  filtered.forEach(e => {
    const key = e.date;
    let g = groups.find(x => x.key === key);
    if (!g) { g = { key, label: relDay(e.date), items: [], net: 0 }; groups.push(g); }
    g.items.push(e); g.net += (e.type === 'income' ? e.amount : -e.amount);
  });

  return (
    <Screen title="Activity"
      right={<NavIconButton name="plus" onClick={() => openAdd()} />}>
      <div style={{ padding: '0 0 4px' }}>
        <SearchBar value={q} onChange={setQ} placeholder="Search activity" />
        <div style={{ padding: '0 16px 14px' }}>
          <Segmented value={sub} onChange={setExpenseSub} options={[
            { id: 'all', label: 'All' },
            { id: 'review', label: review.length ? `Review · ${review.length}` : 'Review' },
          ]} />
        </div>
      </div>

      {sub === 'all' && groups.map(g => (
        <div key={g.key} style={{ marginBottom: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', padding: '0 32px 7px' }}>
            <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', textTransform: 'uppercase', letterSpacing: 0.3 }}>{g.label}</span>
            <span style={{ fontFamily: SF, fontSize: 13, fontWeight: 600, color: g.net >= 0 ? 'var(--pos)' : 'var(--label3)' }}>{g.net >= 0 ? '+' : '−'}{money(Math.abs(g.net), false).replace('-', '')}</span>
          </div>
          <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', margin: '0 16px', overflow: 'hidden' }}>
            {g.items.map((e, i) => {
              const c = catOf(e); const inc = e.type === 'income';
              return (
                <Row key={e.id} icon={{ icon: c.icon, color: c.color }} title={e.merchant} isLast={i === g.items.length - 1}
                  onClick={inc ? undefined : () => openExpense(e)} accessory="none"
                  subtitle={<span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                    <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)' }}>{c.name}</span>
                    {e.account && <><span style={{ color: 'var(--label3)' }}>·</span><span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)' }}>{e.account}</span></>}
                    {e.source === 'gmail' && <Icon name="envelope" size={12} color="var(--label3)" weight={2} />}
                  </span>}
                  value={<span style={{ fontFamily: SF, fontWeight: 600, color: inc ? 'var(--pos)' : 'var(--neg)' }}>{inc ? '+' : '−'}{money(e.amount).replace('-', '').replace('₹', '₹')}</span>} />
              );
            })}
          </div>
        </div>
      ))}

      {sub === 'all' && groups.length === 0 && (
        <div style={{ textAlign: 'center', padding: '60px 40px', color: 'var(--label2)', fontFamily: SF, fontSize: 15 }}>No activity matches “{q}”.</div>
      )}

      {sub === 'review' && (
        <div style={{ padding: '0 16px' }}>
          {review.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '50px 30px' }}>
              <div style={{ display: 'inline-flex', width: 64, height: 64, borderRadius: 18, background: 'color-mix(in srgb, var(--pos) 14%, transparent)', border: '0.5px solid color-mix(in srgb, var(--pos) 40%, transparent)', alignItems: 'center', justifyContent: 'center', marginBottom: 14, boxShadow: '0 0 22px color-mix(in srgb, var(--pos) 30%, transparent)' }}>
                <Icon name="checkmark.circle.fill" size={40} color="var(--pos)" />
              </div>
              <div style={{ fontFamily: SF, fontSize: 20, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.4 }}>Inbox Zero</div>
              <div style={{ fontFamily: SF, fontSize: 15, color: 'var(--label2)', marginTop: 4, lineHeight: 1.4 }}>All imported expenses have been reviewed and added.</div>
            </div>
          ) : (
            <>
              <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', padding: '0 4px 12px', lineHeight: 1.4 }}>
                Auto-detected from receipts in <span style={{ color: 'var(--label)', fontWeight: 500 }}>{PROFILE.email}</span>. Confirm the category, then add.
              </div>
              {review.map(item => <ReviewCard key={item.id} item={item} onConfirm={confirmReview} onDismiss={dismissReview} />)}
            </>
          )}
        </div>
      )}
    </Screen>
  );
}

function ReviewCard({ item, onConfirm, onDismiss }) {
  const [cat, setCat] = useState(item.guessCat);
  const [picking, setPicking] = useState(false);
  const [leaving, setLeaving] = useState(null); // 'add' | 'dismiss'
  const c = CAT[cat];
  const act = (kind) => { setLeaving(kind); setTimeout(() => kind === 'add' ? onConfirm(item, cat) : onDismiss(item), 280); };
  return (
    <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', padding: 16, marginBottom: 12,
      opacity: leaving ? 0 : 1, transform: leaving === 'add' ? 'scale(.96)' : leaving === 'dismiss' ? 'translateX(40px)' : 'none',
      transition: `opacity .3s, transform .3s ${SPRING}` }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <IconTile icon={c.icon} color={c.color} size={42} radius={12} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: SF, fontSize: 17, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.4 }}>{item.merchant}</div>
          <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{item.subject}</div>
        </div>
        <div style={{ fontFamily: SF, fontSize: 20, fontWeight: 300, color: 'var(--neg)', letterSpacing: -0.5 }}>−{money(item.amount).replace('-', '')}</div>
      </div>

      {/* category chooser */}
      <button className="tap" onClick={() => setPicking(p => !p)} style={{ width: '100%', marginTop: 13, border: '0.5px solid var(--sep)', cursor: 'pointer',
        background: 'var(--fill3)', borderRadius: 12, padding: '9px 12px', display: 'flex', alignItems: 'center', gap: 8 }}>
        <Icon name="sparkles" size={15} color="var(--accent)" fill />
        <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)' }}>Suggested</span>
        <span style={{ flex: 1 }} />
        <span style={{ width: 9, height: 9, borderRadius: 3, background: c.color, boxShadow: `0 0 7px ${c.color}` }} />
        <span style={{ fontFamily: SF, fontSize: 15, fontWeight: 500, color: 'var(--label)' }}>{c.name}</span>
        <Icon name="chevron.down" size={14} color="var(--label3)" weight={2.4} />
      </button>
      {picking && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginTop: 10 }}>
          {CATEGORIES.map(cc => (
            <button key={cc.id} className="tap" onClick={() => { setCat(cc.id); setPicking(false); }} style={{
              border: cc.id === cat ? `1.5px solid ${cc.color}` : '1.5px solid transparent', cursor: 'pointer',
              background: 'var(--fill3)', borderRadius: 10, padding: '6px 10px', display: 'flex', alignItems: 'center', gap: 6,
              boxShadow: cc.id === cat ? `0 0 10px color-mix(in srgb, ${cc.color} 45%, transparent)` : 'none' }}>
              <span style={{ width: 8, height: 8, borderRadius: 2.5, background: cc.color }} />
              <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label)' }}>{cc.name}</span>
            </button>
          ))}
        </div>
      )}

      <div style={{ display: 'flex', gap: 10, marginTop: 13 }}>
        <button className="tap" onClick={() => act('dismiss')} style={{ flex: 1, border: '0.5px solid var(--sep)', cursor: 'pointer',
          background: 'var(--fill3)', borderRadius: 12, padding: '11px 0', fontFamily: SF, fontSize: 16, fontWeight: 500, color: 'var(--label2)' }}>Dismiss</button>
        <button className="tap" onClick={() => act('add')} style={{ flex: 2, border: 'none', cursor: 'pointer',
          background: 'var(--accent)', borderRadius: 12, padding: '11px 0', fontFamily: SF, fontSize: 16, fontWeight: 600, color: 'var(--bg)',
          boxShadow: '0 0 18px color-mix(in srgb, var(--accent) 45%, transparent)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          <Icon name="checkmark" size={18} color="var(--bg)" weight={2.6} />Add expense</button>
      </div>
    </div>
  );
}
Object.assign(window, { ExpensesScreen });
