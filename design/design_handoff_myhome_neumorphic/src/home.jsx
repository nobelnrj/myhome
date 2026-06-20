// home.jsx — Overview: liquid cashflow hero (income vs spend) + breakdown.
function HomeScreen({ ctx }) {
  const { expenses, income, budgets, over, reviewCount, nav, openExpense, openNotifications, openAnalytics, style } = ctx;
  const bento = style === 'bento';
  const spent = expenses.reduce((s, e) => s + e.amount, 0);
  const incomeTotal = income.reduce((s, e) => s + e.amount, 0);
  const net = incomeTotal - spent;
  const budgeted = budgets.filter(b => b.limit > 0);
  const budgetTotal = budgeted.reduce((s, b) => s + b.limit, 0);
  const budgetedSpent = budgeted.reduce((s, b) => s + b.spent, 0);
  const remaining = budgetTotal - budgetedSpent;
  const usedPct = budgetTotal > 0 ? Math.round((budgetedSpent / budgetTotal) * 100) : 0;

  // spend by category for donut
  const byCat = {};
  expenses.forEach(e => { byCat[e.cat] = (byCat[e.cat] || 0) + e.amount; });
  const segs = CATEGORIES.map(c => ({ id: c.id, color: c.color, name: c.name, value: byCat[c.id] || 0 }))
    .filter(s => s.value > 0).sort((a, b) => b.value - a.value);
  const top = segs.slice(0, 4);

  const recent = expenses.slice(0, 4);
  const recentIncome = income.slice(0, 2);
  const dayLabel = d => new Date(d + 'T00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  const ULTRA = { fontFamily: SF, fontWeight: 200 };

  return (
    <Screen title="Overview"
      right={<NavIconButton name={reviewCount > 0 ? 'bell.badge' : 'bell'} onClick={openNotifications} color="var(--accent)" />}>
      <div style={{ padding: '0 16px 22px' }}>
        <div style={{ fontFamily: SF, fontSize: 12, fontWeight: 600, color: 'var(--label2)', letterSpacing: 1.4, marginBottom: 12, textTransform: 'uppercase' }}>June 2026</div>

        {bento && <BentoHero net={net} incomeTotal={incomeTotal} spent={spent} usedPct={usedPct} budgetTotal={budgetTotal} remaining={remaining} budgetedLen={budgeted.length} openAnalytics={openAnalytics} nav={nav} />}

        {/* ── liquid cashflow hero ── */}
        <div style={{ position: 'relative', borderRadius: 28, padding: '20px 22px 22px', overflow: 'hidden', isolation: 'isolate', display: bento ? 'none' : undefined,
          background: 'var(--glass-tint-strong)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)',
          border: 'var(--glass-border)', boxShadow: 'var(--glass-shadow-float)' }}>
          {/* refracted light + accent wash */}
          <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none',
            background: 'linear-gradient(180deg, rgba(255,255,255,0.10), rgba(255,255,255,0) 38%), radial-gradient(120% 90% at 100% -10%, color-mix(in srgb, var(--pos) 18%, transparent), transparent 55%)' }} />

          <div style={{ position: 'relative', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontFamily: SF, fontSize: 12, fontWeight: 600, letterSpacing: 1, color: 'var(--label2)' }}>NET CASH FLOW</span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: SF, fontSize: 11.5, fontWeight: 600, letterSpacing: 0.3,
              color: net >= 0 ? 'var(--pos)' : 'var(--neg)', background: net >= 0 ? 'color-mix(in srgb, var(--pos) 14%, transparent)' : 'color-mix(in srgb, var(--neg) 14%, transparent)',
              border: `0.5px solid ${net >= 0 ? 'color-mix(in srgb, var(--pos) 40%, transparent)' : 'color-mix(in srgb, var(--neg) 40%, transparent)'}`,
              borderRadius: 20, padding: '4px 10px' }}>
              <Icon name={net >= 0 ? 'arrow.up' : 'arrow.down'} size={12} color={net >= 0 ? 'var(--pos)' : 'var(--neg)'} weight={2.6} />
              {net >= 0 ? 'Positive' : 'Negative'}
            </span>
          </div>

          <div style={{ position: 'relative', display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 4 }}>
            <span style={{ ...ULTRA, fontSize: 34, color: net >= 0 ? 'var(--pos)' : 'var(--neg)', letterSpacing: -1, flexShrink: 0 }}>{net >= 0 ? '+' : '−'}</span>
            <RollingMoney value={Math.abs(net)} animateOnMount style={{ ...ULTRA, fontSize: 56, color: net >= 0 ? 'var(--pos)' : 'var(--neg)', letterSpacing: -2.5, lineHeight: 1,
              textShadow: `0 0 28px color-mix(in srgb, ${net >= 0 ? 'var(--pos)' : 'var(--neg)'} 45%, transparent)` }} />
          </div>

          {/* income / spent split */}
          <div style={{ position: 'relative', display: 'flex', gap: 10, marginTop: 18 }}>
            <Flow label="Income" amount={incomeTotal} color="var(--pos)" icon="arrow.down.left" />
            <Flow label="Spent" amount={spent} color="var(--neg)" icon="arrow.up.right" />
          </div>

          {/* budget usage */}
          {budgetTotal > 0 ? (
            <div style={{ position: 'relative', marginTop: 18 }}>
              <div style={{ height: 8, borderRadius: 8, background: 'var(--fill3)', overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${Math.min(usedPct, 100)}%`, borderRadius: 8,
                  background: remaining >= 0 ? 'linear-gradient(90deg, var(--glow), var(--pos))' : 'var(--neg)',
                  boxShadow: `0 0 10px ${remaining >= 0 ? 'var(--glow)' : 'var(--neg)'}`, transition: `width .7s ${SPRING}` }} />
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 10 }}>
                <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)' }}>{usedPct}% of {money(budgetTotal, false)} budget</span>
                <span style={{ fontFamily: SF, fontSize: 13, fontWeight: 600, color: remaining >= 0 ? 'var(--label)' : 'var(--neg)' }}>
                  {money(Math.abs(remaining), false)} {remaining >= 0 ? 'left' : 'over'}</span>
              </div>
            </div>
          ) : (
            <button className="tap" onClick={() => nav('budgets')} style={{ position: 'relative', marginTop: 16, border: '0.5px solid var(--sep)', cursor: 'pointer',
              background: 'var(--fill3)', borderRadius: 12, padding: '11px 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%',
              fontFamily: SF, fontSize: 14, color: 'var(--label)', fontWeight: 500 }}>
              Set a budget to track your spending
              <Icon name="chevron.right" size={15} color="var(--accent)" weight={2.5} />
            </button>
          )}
        </div>

        {/* review inbox banner */}
        {reviewCount > 0 && (
          <button className="tap" onClick={() => nav('expenses', { review: true })} style={{
            width: '100%', marginTop: 14, border: 'var(--glass-border)', cursor: 'pointer', textAlign: 'left',
            background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', padding: 14, display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ width: 40, height: 40, borderRadius: 12, background: 'color-mix(in srgb, var(--accent) 18%, transparent)', border: '0.5px solid color-mix(in srgb, var(--accent) 45%, transparent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, boxShadow: '0 0 16px color-mix(in srgb, var(--accent) 35%, transparent)' }}>
              <Icon name="envelope" size={21} color="var(--accent)" weight={2} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: SF, fontSize: 16, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.3 }}>{reviewCount} {reviewCount === 1 ? 'expense' : 'expenses'} to review</div>
              <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', marginTop: 1 }}>Imported from Gmail · tap to confirm</div>
            </div>
            <Icon name="chevron.right" size={16} color="var(--label3)" weight={2.5} />
          </button>
        )}

        {/* analytics entry — visible in every style except bento (it lives in the bento grid) */}
        {!bento && (
          <button className="tap" onClick={openAnalytics} style={{
            width: '100%', marginTop: 14, border: 'var(--glass-border)', cursor: 'pointer', textAlign: 'left',
            background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', padding: 14, display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ width: 40, height: 40, borderRadius: 12, background: 'var(--glow)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, boxShadow: '0 0 18px color-mix(in srgb, var(--glow) 55%, transparent)' }}>
              <Icon name="chart.line" size={22} color="#1A1404" weight={2.4} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: SF, fontSize: 16, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.3 }}>Analytics</div>
              <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', marginTop: 1 }}>Trends, insights &amp; breakdowns</div>
            </div>
            <Icon name="chevron.right" size={16} color="var(--label3)" weight={2.5} />
          </button>
        )}
      </div>

      {/* donut breakdown */}
      <div style={{ fontFamily: SF, fontSize: 22, fontWeight: 700, letterSpacing: -0.4, color: 'var(--label)', padding: '0 16px 12px' }}>Where it’s going</div>
      <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', margin: '0 16px 22px', padding: 18,
        display: 'flex', alignItems: 'center', gap: 18 }}>
        <Donut segments={segs} size={132} thickness={18}
          center={<><div style={{ fontFamily: SF, fontSize: 10.5, color: 'var(--label2)', fontWeight: 600, letterSpacing: 0.6 }}>SPENT</div>
            <RollingMoney value={spent} style={{ fontFamily: SF, fontSize: 21, fontWeight: 300, color: 'var(--label)', letterSpacing: -0.5 }} /></>} />
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 11 }}>
          {top.map(s => (
            <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
              <span style={{ width: 9, height: 9, borderRadius: 3, background: s.color, flexShrink: 0, boxShadow: `0 0 7px ${s.color}` }} />
              <span style={{ flex: 1, fontFamily: SF, fontSize: 14, color: 'var(--label)', letterSpacing: -0.2, whiteSpace: 'nowrap' }}>{s.name}</span>
              <span style={{ fontFamily: SF, fontSize: 14, color: 'var(--label2)', fontWeight: 500 }}>{money(s.value, false)}</span>
            </div>
          ))}
        </div>
      </div>

      {/* budgets glance */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', padding: '0 16px 12px' }}>
        <div style={{ fontFamily: SF, fontSize: 22, fontWeight: 700, letterSpacing: -0.4, color: 'var(--label)' }}>Budgets</div>
        <button className="tap" onClick={() => nav('budgets')} style={{ border: 'none', background: 'none', cursor: 'pointer', fontFamily: SF, fontSize: 15, color: 'var(--accent)' }}>See all</button>
      </div>
      {budgeted.length > 0 ? (
        <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', margin: '0 16px 22px', padding: '4px 16px' }}>
          {budgeted.slice(0, 3).map((b, i, arr) => {
            const c = CAT[b.cat]; const frac = b.spent / b.limit; const isOver = b.spent > b.limit;
            return (
              <div key={b.cat} style={{ padding: '13px 0', borderBottom: i < arr.length - 1 ? '0.5px solid var(--sep)' : 'none' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 9 }}>
                  <IconTile icon={c.icon} color={c.color} size={26} />
                  <span style={{ flex: 1, fontFamily: SF, fontSize: 16, color: 'var(--label)', letterSpacing: -0.3 }}>{c.name}</span>
                  <span style={{ fontFamily: SF, fontSize: 14, color: isOver ? 'var(--neg)' : 'var(--label2)', fontWeight: 500 }}>
                    {money(b.spent, false)} <span style={{ color: 'var(--label3)' }}>/ {money(b.limit, false)}</span></span>
                </div>
                <ProgressBar frac={frac} color={isOver ? 'var(--neg)' : c.color} />
              </div>
            );
          })}
        </div>
      ) : (
        <button className="tap" onClick={() => nav('budgets')} style={{ width: '100%', textAlign: 'left', border: 'var(--glass-border)', cursor: 'pointer',
          background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', margin: '0 16px 22px', padding: 16, display: 'flex', alignItems: 'center', gap: 12 }}>
          <IconTile icon="chart.pie" color="var(--accent)" size={34} radius={9} />
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: SF, fontSize: 16, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.3 }}>Set a budget</div>
            <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', marginTop: 1 }}>Track spending by category</div>
          </div>
          <Icon name="chevron.right" size={16} color="var(--label3)" weight={2.5} />
        </button>
      )}

      {/* income glance */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', padding: '0 16px 12px' }}>
        <div style={{ fontFamily: SF, fontSize: 22, fontWeight: 700, letterSpacing: -0.4, color: 'var(--label)' }}>Income</div>
        <button className="tap" onClick={() => nav('expenses')} style={{ border: 'none', background: 'none', cursor: 'pointer', fontFamily: SF, fontSize: 15, color: 'var(--accent)' }}>See all</button>
      </div>
      <GroupedList>
        {recentIncome.map(e => {
          const c = INCOME_CAT[e.cat];
          return (
            <Row key={e.id} iconNode={<IconTile icon={c.icon} color={c.color} size={30} />} title={e.merchant}
              subtitle={`${c.name} · ${dayLabel(e.date)}`}
              value={<span style={{ fontFamily: SF, fontWeight: 600, color: 'var(--pos)' }}>+{money(e.amount, false)}</span>}
              accessory="none" />
          );
        })}
      </GroupedList>

      {/* recent expenses */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', padding: '0 16px 12px' }}>
        <div style={{ fontFamily: SF, fontSize: 22, fontWeight: 700, letterSpacing: -0.4, color: 'var(--label)' }}>Recent</div>
        <button className="tap" onClick={() => nav('expenses')} style={{ border: 'none', background: 'none', cursor: 'pointer', fontFamily: SF, fontSize: 15, color: 'var(--accent)' }}>See all</button>
      </div>
      <GroupedList>
        {recent.map(e => {
          const c = CAT[e.cat];
          return (
            <Row key={e.id} icon={{ icon: c.icon, color: c.color }} title={e.merchant}
              subtitle={`${c.name} · ${dayLabel(e.date)}`} value={money(e.amount)} valueColor="var(--label)"
              accessory="none" onClick={() => openExpense(e)} />
          );
        })}
      </GroupedList>
    </Screen>
  );
}

// income/spent stat tile inside the hero
function Flow({ label, amount, color, icon }) {
  return (
    <div style={{ flex: 1, background: 'var(--fill3)', border: '0.5px solid var(--sep)', borderRadius: 16, padding: '11px 13px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
        <span style={{ width: 22, height: 22, borderRadius: 7, display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: `color-mix(in srgb, ${color} 16%, transparent)`, boxShadow: `0 0 10px color-mix(in srgb, ${color} 30%, transparent)` }}>
          <Icon name={icon} size={14} color={color} weight={2.6} />
        </span>
        <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', fontWeight: 500 }}>{label}</span>
      </div>
      <RollingMoney value={amount} style={{ display: 'block', marginTop: 7, fontFamily: SF, fontSize: 21, fontWeight: 300, color: 'var(--label)', letterSpacing: -0.6 }} />
    </div>
  );
}

// ── Bento-grid overview (shown only in the Bento UI style) ──
function BentoTile({ children, span = 1, style = {}, onClick, accent = false }) {
  return (
    <div className={onClick ? 'tap' : ''} onClick={onClick} style={{
      gridColumn: span === 2 ? 'span 2' : 'span 1', position: 'relative', overflow: 'hidden',
      borderRadius: 'var(--card-radius)', padding: 16, cursor: onClick ? 'pointer' : 'default',
      background: accent ? 'var(--glow)' : 'var(--glass-tint)', border: accent ? 'none' : 'var(--glass-border)',
      boxShadow: 'var(--card-shadow)', ...style }}>
      {children}
    </div>
  );
}

function BentoHero({ net, incomeTotal, spent, usedPct, budgetTotal, remaining, budgetedLen, openAnalytics, nav }) {
  const tileLabel = { fontFamily: SF, fontSize: 11.5, fontWeight: 600, letterSpacing: 0.6, color: 'var(--label2)', textTransform: 'uppercase' };
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
      {/* net cash flow — full width */}
      <BentoTile span={2} style={{ padding: '18px 20px 20px' }}>
        <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none',
          background: 'radial-gradient(120% 100% at 100% -10%, color-mix(in srgb, ' + (net >= 0 ? 'var(--pos)' : 'var(--neg)') + ' 14%, transparent), transparent 60%)' }} />
        <div style={{ position: 'relative', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={tileLabel}>Net cash flow</span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontFamily: SF, fontSize: 11.5, fontWeight: 600,
            color: net >= 0 ? 'var(--pos)' : 'var(--neg)', background: net >= 0 ? 'color-mix(in srgb, var(--pos) 14%, transparent)' : 'color-mix(in srgb, var(--neg) 14%, transparent)',
            border: `0.5px solid ${net >= 0 ? 'color-mix(in srgb, var(--pos) 40%, transparent)' : 'color-mix(in srgb, var(--neg) 40%, transparent)'}`, borderRadius: 20, padding: '3px 9px' }}>
            <Icon name={net >= 0 ? 'arrow.up' : 'arrow.down'} size={11} color={net >= 0 ? 'var(--pos)' : 'var(--neg)'} weight={2.6} />
            {net >= 0 ? 'Positive' : 'Negative'}
          </span>
        </div>
        <div style={{ position: 'relative', display: 'flex', alignItems: 'baseline', gap: 3, marginTop: 4 }}>
          <span style={{ fontFamily: SF, fontWeight: 200, fontSize: 26, color: net >= 0 ? 'var(--pos)' : 'var(--neg)', letterSpacing: -1 }}>{net >= 0 ? '+' : '−'}</span>
          <RollingMoney value={Math.abs(net)} animateOnMount style={{ fontFamily: SF, fontWeight: 200, fontSize: 46, color: net >= 0 ? 'var(--pos)' : 'var(--neg)', letterSpacing: -2, lineHeight: 1 }} />
        </div>
      </BentoTile>

      {/* income */}
      <BentoTile>
        <div style={tileLabel}>Income</div>
        <RollingMoney value={incomeTotal} cents={false} style={{ display: 'block', marginTop: 8, fontFamily: SF, fontWeight: 300, fontSize: 24, color: 'var(--pos)', letterSpacing: -0.8 }} />
      </BentoTile>
      {/* spent */}
      <BentoTile>
        <div style={tileLabel}>Spent</div>
        <RollingMoney value={spent} cents={false} style={{ display: 'block', marginTop: 8, fontFamily: SF, fontWeight: 300, fontSize: 24, color: 'var(--neg)', letterSpacing: -0.8 }} />
      </BentoTile>

      {/* budget usage */}
      <BentoTile onClick={() => nav('budgets')}>
        <div style={tileLabel}>{budgetTotal > 0 ? (remaining >= 0 ? 'Budget left' : 'Over budget') : 'Budgets'}</div>
        {budgetTotal > 0 ? (
          <>
            <div style={{ fontFamily: SF, fontWeight: 300, fontSize: 24, color: remaining >= 0 ? 'var(--label)' : 'var(--neg)', letterSpacing: -0.8, marginTop: 8 }}>{money(Math.abs(remaining), false)}</div>
            <div style={{ height: 6, borderRadius: 6, background: 'var(--fill3)', overflow: 'hidden', marginTop: 9 }}>
              <div style={{ height: '100%', width: `${Math.min(usedPct, 100)}%`, borderRadius: 6,
                background: remaining >= 0 ? 'linear-gradient(90deg, var(--glow), var(--pos))' : 'var(--neg)' }} />
            </div>
          </>
        ) : (
          <div style={{ fontFamily: SF, fontSize: 14, color: 'var(--label2)', marginTop: 10 }}>Set a budget →</div>
        )}
      </BentoTile>

      {/* analytics — accent yellow tile */}
      <BentoTile accent onClick={openAnalytics} style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
        <Icon name="chart.line" size={26} color="#1A1404" weight={2.4} />
        <div>
          <div style={{ fontFamily: SF, fontSize: 17, fontWeight: 700, color: '#1A1404', letterSpacing: -0.3, marginTop: 12 }}>Analytics</div>
          <div style={{ fontFamily: SF, fontSize: 12.5, fontWeight: 500, color: 'rgba(26,20,4,0.66)', marginTop: 1 }}>Trends &amp; insights</div>
        </div>
      </BentoTile>
    </div>
  );
}
Object.assign(window, { HomeScreen, BentoHero });
