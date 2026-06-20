// budgets.jsx — Budgets overview, per-category progress, and edit sheet.
function BudgetsScreen({ ctx }) {
  const { budgets, onEditBudget } = ctx;
  const setBudgets = budgets.filter(b => b.limit > 0);
  const totalLimit = setBudgets.reduce((s, b) => s + b.limit, 0);
  const totalSpent = setBudgets.reduce((s, b) => s + b.spent, 0);
  const remaining = totalLimit - totalSpent;
  const overCount = setBudgets.filter(b => b.spent > b.limit).length;
  const ringColor = remaining < 0 ? 'var(--red)' : (totalSpent / totalLimit) > 0.85 ? 'var(--orange)' : 'var(--green)';

  // order: budgeted (over→high frac) first, then categories with spend but no budget, then empty
  const ordered = [...budgets].sort((a, b) => {
    const fa = a.limit > 0 ? a.spent / a.limit : (a.spent > 0 ? -0.5 : -1);
    const fb = b.limit > 0 ? b.spent / b.limit : (b.spent > 0 ? -0.5 : -1);
    return fb - fa;
  });

  return (
    <Screen title="Budgets"
      right={<NavButton onClick={() => onEditBudget(ordered.find(b => b.limit === 0)?.cat || ordered[0].cat)}>Set budget</NavButton>}>
      {setBudgets.length > 0 ? (
        <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', margin: '0 16px 22px', padding: 20, display: 'flex', alignItems: 'center', gap: 20 }}>
          <Donut size={120} thickness={18} segments={[{ color: ringColor, value: Math.min(totalSpent, totalLimit) }, { color: 'transparent', value: Math.max(totalLimit - totalSpent, 0) }]}
            center={<><div style={{ fontFamily: SF, fontSize: 24, fontWeight: 300, color: 'var(--label)', letterSpacing: -0.6 }}>{Math.round((totalSpent / totalLimit) * 100)}%</div>
              <div style={{ fontFamily: SF, fontSize: 11, color: 'var(--label2)', fontWeight: 500 }}>used</div></>} />
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', fontWeight: 500 }}>{remaining >= 0 ? 'LEFT TO SPEND' : 'OVER BUDGET'}</div>
            <RollingMoney value={Math.abs(remaining)} style={{ fontFamily: SF, fontSize: 30, fontWeight: 200, letterSpacing: -1, color: remaining >= 0 ? 'var(--label)' : 'var(--neg)' }} />
            <div style={{ fontFamily: SF, fontSize: 14, color: 'var(--label2)', marginTop: 3 }}>{money(totalSpent, false)} of {money(totalLimit, false)}</div>
            {overCount > 0 && (
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 9, background: 'color-mix(in srgb, var(--red) 12%, transparent)', borderRadius: 7, padding: '4px 9px' }}>
                <Icon name="flag" size={13} color="var(--red)" fill weight={2} />
                <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--red)', fontWeight: 500 }}>{overCount} over limit</span>
              </div>
            )}
          </div>
        </div>
      ) : (
        <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', margin: '0 16px 22px', padding: '22px 18px', textAlign: 'center' }}>
          <div style={{ display: 'inline-flex', width: 52, height: 52, borderRadius: 14, background: 'var(--fill3)', alignItems: 'center', justifyContent: 'center', marginBottom: 10 }}>
            <Icon name="chart.pie" size={28} color="var(--accent)" /></div>
          <div style={{ fontFamily: SF, fontSize: 18, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.4 }}>Set a budget to track spending</div>
          <div style={{ fontFamily: SF, fontSize: 14, color: 'var(--label2)', marginTop: 4, lineHeight: 1.4 }}>Tap any category below to set a monthly limit.</div>
        </div>
      )}

      <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', padding: '0 32px 7px', textTransform: 'uppercase', letterSpacing: -0.08 }}>This month — June 2026</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: '0 16px' }}>
        {ordered.map(b => {
          const c = CAT[b.cat]; const has = b.limit > 0; const frac = has ? b.spent / b.limit : 0; const isOver = has && b.spent > b.limit;
          const left = b.limit - b.spent;
          const barColor = isOver ? 'var(--red)' : frac > 0.85 ? 'var(--orange)' : c.color;
          return (
            <button key={b.cat} className="tap" onClick={() => onEditBudget(b.cat)} style={{ textAlign: 'left', border: 'none', cursor: 'pointer',
              background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', padding: 16 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 11, marginBottom: has ? 11 : 0 }}>
                <IconTile icon={c.icon} color={c.color} size={34} radius={9} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: SF, fontSize: 16, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.3 }}>{c.name}</div>
                  <div style={{ fontFamily: SF, fontSize: 13, color: !has ? 'var(--label3)' : isOver ? 'var(--red)' : 'var(--label2)', marginTop: 1 }}>
                    {!has ? 'No budget set' : isOver ? `${money(-left, false)} over` : `${money(left, false)} left`}</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontFamily: SF, fontSize: 17, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.4 }}>{money(b.spent, false)}</div>
                  {has && <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label3)' }}>of {money(b.limit, false)}</div>}
                </div>
                <Icon name="pencil" size={17} color="var(--label3)" />
              </div>
              {has && <ProgressBar frac={frac} color={barColor} height={8} />}
            </button>
          );
        })}
      </div>
    </Screen>
  );
}

// Budget edit sheet — set / clear a category's monthly limit with the decimal keypad.
function BudgetEditSheet({ open, cat, currentLimit, spent, onClose, onSave, onClear }) {
  const [amount, setAmount] = useState('');
  useEffect(() => { if (open) setAmount(currentLimit > 0 ? String(currentLimit) : ''); }, [open, currentLimit]);
  const c = cat ? CAT[cat] : null;
  const num = parseFloat(amount || '0') || 0;
  const press = (k) => setAmount(prev => {
    if (k === 'del') return prev.slice(0, -1);
    if (k === '.') return prev.includes('.') ? prev : (prev === '' ? '0.' : prev + '.');
    const [, dec] = prev.split('.'); if (dec && dec.length >= 2) return prev;
    if (prev === '0') return k; return prev + k;
  });
  return (
    <Sheet open={open} onClose={onClose} title={c ? `${c.name} Budget` : 'Budget'}
      left={<NavButton onClick={onClose}>Cancel</NavButton>}
      right={<NavButton prominent disabled={num <= 0} onClick={() => onSave(cat, Math.round(num * 100) / 100)}>Save</NavButton>}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        <div style={{ flex: 1, overflowY: 'auto' }}>
          {c && (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '18px 0 8px' }}>
              <IconTile icon={c.icon} color={c.color} size={56} radius={15} />
              <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', marginTop: 14, fontWeight: 500, letterSpacing: 0.2 }}>MONTHLY LIMIT</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 2, marginTop: 2 }}>
                <span style={{ fontFamily: SF, fontSize: 34, fontWeight: 300, color: num > 0 ? 'var(--label)' : 'var(--label3)', letterSpacing: -1 }}>₹</span>
                <span style={{ fontFamily: SF, fontSize: 52, fontWeight: 200, letterSpacing: -2, color: num > 0 ? 'var(--label)' : 'var(--label3)' }}>{amount === '' ? '0' : amount}</span>
              </div>
              <div style={{ fontFamily: SF, fontSize: 14, color: 'var(--label2)', marginTop: 6 }}>
                {money(spent, false)} spent so far{num > 0 ? ` · ${money(num - spent, false)} ${num - spent >= 0 ? 'left' : 'over'}` : ''}</div>
            </div>
          )}
          {currentLimit > 0 && (
            <GroupedList style={{ marginTop: 18 }}>
              <Row accessory="none" onClick={() => onClear(cat)}
                children={<div style={{ textAlign: 'center', fontFamily: SF, fontSize: 17, color: 'var(--red)' }}>Remove Budget</div>} />
            </GroupedList>
          )}
        </div>
        <DecimalKeypad onPress={press} onDone={() => num > 0 && onSave(cat, Math.round(num * 100) / 100)} />
      </div>
    </Sheet>
  );
}

Object.assign(window, { BudgetsScreen, BudgetEditSheet });
