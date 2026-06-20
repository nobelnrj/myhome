// addexpense.jsx — Add / Edit expense sheet: keypad + graphical date picker + category/account pickers.
function AddExpenseSheet({ open, editing, onClose, onSave, onDelete }) {
  const [amount, setAmount] = useState('');
  const [merchant, setMerchant] = useState('');
  const [cat, setCat] = useState('groceries');
  const [account, setAccount] = useState(ACCOUNTS[0].label);
  const [note, setNote] = useState('');
  const [date, setDate] = useState(TODAY);
  const [focus, setFocus] = useState('amount'); // 'amount' | 'cal' | null
  const [picking, setPicking] = useState(null);   // 'category' | 'account' | null

  useEffect(() => {
    if (open) {
      if (editing) {
        setAmount(String(editing.amount)); setMerchant(editing.merchant); setCat(editing.cat);
        setAccount(editing.account || ACCOUNTS[0].label); setNote(editing.note || ''); setDate(editing.date); setFocus(null);
      } else {
        setAmount(''); setMerchant(''); setCat('groceries'); setAccount(ACCOUNTS[0].label); setNote(''); setDate(TODAY); setFocus('amount');
      }
      setPicking(null);
    }
  }, [open, editing]);

  const num = parseFloat(amount || '0') || 0;
  const valid = num > 0 && merchant.trim().length > 0;
  const c = CAT[cat];
  const dateLabel = date === TODAY ? 'Today' : new Date(date + 'T00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

  const press = (k) => setAmount(prev => {
    if (k === 'del') return prev.slice(0, -1);
    if (k === '.') return prev.includes('.') ? prev : (prev === '' ? '0.' : prev + '.');
    const [, dec] = prev.split('.');
    if (dec && dec.length >= 2) return prev;
    if (prev === '0') return k;
    return prev + k;
  });
  const save = () => onSave({
    id: editing ? editing.id : 'x' + Date.now(), merchant: merchant.trim(), cat, account,
    amount: Math.round(num * 100) / 100, date, note: note.trim(), source: editing ? editing.source : 'manual',
  });
  const display = amount === '' ? '0' : amount;

  return (
    <Sheet open={open} onClose={onClose} title={editing ? 'Edit Expense' : 'New Expense'}
      left={<NavButton onClick={onClose}>Cancel</NavButton>}
      right={<NavButton prominent disabled={!valid} onClick={save}>{editing ? 'Save' : 'Add'}</NavButton>}>
      <div style={{ position: 'relative', height: '100%', display: 'flex', flexDirection: 'column' }}>
        <div className="noscroll" style={{ flex: 1, overflowY: 'auto', paddingBottom: 8 }}>
          {/* amount hero */}
          <button className="tap" onClick={() => setFocus('amount')} style={{ width: '100%', border: 'none', background: 'none', cursor: 'pointer',
            padding: '14px 0 18px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 2 }}>
            <span style={{ fontFamily: SF, fontSize: 38, fontWeight: 300, color: num > 0 ? 'var(--label)' : 'var(--label3)', letterSpacing: -1 }}>₹</span>
            <span style={{ fontFamily: SF, fontSize: 56, fontWeight: 200, letterSpacing: -2,
              color: num > 0 || amount ? 'var(--label)' : 'var(--label3)',
              borderBottom: focus === 'amount' ? '2px solid var(--accent)' : '2px solid transparent', paddingBottom: 2 }}>{display}</span>
          </button>

          <GroupedList>
            <Row accessory="none" leftInset={16} iconNode={<Icon name="pencil" size={20} color="var(--label2)" />}
              children={<input value={merchant} onFocus={() => setFocus(null)} onChange={e => setMerchant(e.target.value)} placeholder="Merchant"
                style={{ width: '100%', border: 'none', background: 'none', outline: 'none', fontFamily: SF, fontSize: 17, letterSpacing: -0.4, color: 'var(--label)' }} />} />
            <Row onClick={() => { setPicking('category'); setFocus(null); }} accessory="chevron"
              iconNode={<IconTile icon={c.icon} color={c.color} size={28} />} title="Category" value={c.name} valueColor="var(--label2)" />
            <Row onClick={() => { setPicking('account'); setFocus(null); }} accessory="chevron"
              iconNode={<Icon name="creditcard" size={22} color="var(--accent)" />} title="Account" value={account} valueColor="var(--label2)" />
          </GroupedList>

          {/* date — tap to reveal graphical calendar */}
          <GroupedList>
            <Row accessory={<Icon name="chevron.down" size={15} color="var(--label3)" weight={2.4}
              style={{ transform: focus === 'cal' ? 'rotate(180deg)' : 'none', transition: 'transform .25s' }} />}
              iconNode={<Icon name="calendar" size={22} color="var(--accent)" />} title="Date"
              value={<span style={{ color: focus === 'cal' ? 'var(--accent)' : 'var(--label2)' }}>{dateLabel}</span>}
              onClick={() => setFocus(f => f === 'cal' ? null : 'cal')} />
            <div style={{ maxHeight: focus === 'cal' ? 400 : 0, overflow: 'hidden', transition: 'max-height .32s cubic-bezier(.32,.72,0,1)' }}>
              <div style={{ padding: '8px 14px 14px' }}>
                <MonthCalendar value={date} onSelect={(d) => setDate(d)} />
              </div>
            </div>
          </GroupedList>

          <GroupedList>
            <Row accessory="none" leftInset={16} iconNode={<Icon name="note" size={20} color="var(--label2)" />}
              children={<input value={note} onFocus={() => setFocus(null)} onChange={e => setNote(e.target.value)} placeholder="Add a note"
                style={{ width: '100%', border: 'none', background: 'none', outline: 'none', fontFamily: SF, fontSize: 17, letterSpacing: -0.4, color: 'var(--label)' }} />} />
          </GroupedList>

          {editing && (
            <GroupedList>
              <Row accessory="none" onClick={() => onDelete(editing)}
                children={<div style={{ textAlign: 'center', fontFamily: SF, fontSize: 17, color: 'var(--red)' }}>Delete Expense</div>} />
            </GroupedList>
          )}
        </div>

        {/* decimal keypad */}
        <div style={{ flexShrink: 0, maxHeight: focus === 'amount' ? 300 : 0, overflow: 'hidden', transition: 'max-height .3s cubic-bezier(.32,.72,0,1)' }}>
          <DecimalKeypad onPress={press} onDone={() => setFocus(null)} />
        </div>
      </div>

      <PickerOverlay open={picking === 'category'} title="Category" onClose={() => setPicking(null)}
        items={CATEGORIES.map(cc => ({ id: cc.id, label: cc.name, iconNode: <IconTile icon={cc.icon} color={cc.color} size={30} /> }))}
        value={cat} onPick={(id) => { setCat(id); setPicking(null); }} />
      <PickerOverlay open={picking === 'account'} title="Account" onClose={() => setPicking(null)}
        items={ACCOUNTS.map(a => ({ id: a.label, label: a.label, sub: a.kind, iconNode: <IconTile icon="creditcard" color="var(--accent)" size={30} /> }))}
        value={account} onPick={(id) => { setAccount(id); setPicking(null); }} />
    </Sheet>
  );
}

function DecimalKeypad({ onPress, onDone }) {
  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'];
  return (
    <div style={{ background: 'transparent', borderTop: '0.5px solid var(--sep)', padding: '10px 6px 8px' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 7 }}>
        {keys.map(k => (
          <button key={k} className="keycap" onClick={() => onPress(k)} style={{ height: 48, border: '0.5px solid rgba(255,255,255,0.06)', borderRadius: 12,
            background: 'var(--bg-elevated2)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.08)' }}>
            {k === 'del' ? <Icon name="delete.left" size={24} color="var(--label)" weight={1.8} />
              : <span style={{ fontFamily: SF, fontSize: 26, fontWeight: 300, color: 'var(--label)' }}>{k}</span>}
          </button>
        ))}
      </div>
      <button className="tap" onClick={onDone} style={{ width: '100%', marginTop: 8, border: 'none', borderRadius: 13,
        background: 'var(--accent)', color: 'var(--bg)', cursor: 'pointer', padding: '11px 0', fontFamily: SF, fontSize: 16, fontWeight: 600,
        boxShadow: '0 0 18px color-mix(in srgb, var(--accent) 45%, transparent)' }}>Done</button>
    </div>
  );
}

// Generic slide-over list picker (Category / Account)
function PickerOverlay({ open, title, items, value, onPick, onClose }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 5, pointerEvents: open ? 'auto' : 'none',
      transform: open ? 'translateX(0)' : 'translateX(100%)', transition: 'transform .32s cubic-bezier(.32,.72,0,1)',
      background: 'var(--chrome)', backdropFilter: 'var(--chrome-blur)', WebkitBackdropFilter: 'var(--chrome-blur)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ height: 56, display: 'flex', alignItems: 'center', padding: '0 12px', flexShrink: 0 }}>
        <NavButton onClick={onClose}><Icon name="chevron.left" size={20} color="var(--accent)" weight={2.4} />Back</NavButton>
        <div style={{ flex: 1, textAlign: 'center', fontFamily: SF, fontSize: 17, fontWeight: 600, color: 'var(--label)', marginLeft: -60 }}>{title}</div>
      </div>
      <div className="noscroll" style={{ flex: 1, overflowY: 'auto', paddingTop: 4 }}>
        <GroupedList>
          {items.map((it, i) => (
            <Row key={it.id} isLast={i === items.length - 1} onClick={() => onPick(it.id)} accessory="none"
              iconNode={it.iconNode} title={it.label} subtitle={it.sub}
              value={it.id === value ? <Icon name="checkmark" size={20} color="var(--accent)" weight={2.6} /> : null} />
          ))}
        </GroupedList>
      </div>
    </div>
  );
}

Object.assign(window, { AddExpenseSheet, DecimalKeypad });
