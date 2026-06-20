// notes.jsx — Notes · Reminders · Calendar, plus Note editor, Reminder sheet, Notifications route.
function NotesScreen({ ctx }) {
  const { notes, reminders, toggleReminder, notesSub, setNotesSub, openNote, openNewNote } = ctx;
  const [q, setQ] = useState('');
  const filtered = notes.filter(n => !q || n.title.toLowerCase().includes(q.toLowerCase())
    || (n.body || '').toLowerCase().includes(q.toLowerCase())
    || (n.items || []).some(it => it.text.toLowerCase().includes(q.toLowerCase())));

  return (
    <Screen title="Notes"
      right={notesSub === 'notes' ? <NavIconButton name="plus" onClick={openNewNote} /> : null}>
      {notesSub === 'notes' && <SearchBar value={q} onChange={setQ} placeholder="Search notes" />}
      <div style={{ padding: '0 16px 16px' }}>
        <Segmented value={notesSub} onChange={setNotesSub} options={[
          { id: 'notes', label: 'Notes' }, { id: 'reminders', label: 'Reminders' }, { id: 'calendar', label: 'Calendar' }]} />
      </div>
      {notesSub === 'notes' && <NotesList notes={filtered} openNote={openNote} q={q} />}
      {notesSub === 'reminders' && <RemindersList reminders={reminders} toggle={toggleReminder} />}
      {notesSub === 'calendar' && <CalendarTab />}
    </Screen>
  );
}

function NotesList({ notes, openNote, q }) {
  if (notes.length === 0) {
    return <div style={{ textAlign: 'center', padding: '60px 40px' }}>
      <div style={{ display: 'inline-flex', width: 60, height: 60, borderRadius: 16, background: 'var(--fill3)', alignItems: 'center', justifyContent: 'center', marginBottom: 12 }}>
        <Icon name="note" size={34} color="var(--label3)" /></div>
      <div style={{ fontFamily: SF, fontSize: 20, fontWeight: 600, color: 'var(--label)' }}>{q ? 'No matches' : 'No Notes Yet'}</div>
      <div style={{ fontFamily: SF, fontSize: 15, color: 'var(--label2)', marginTop: 4 }}>{q ? `Nothing for “${q}”.` : 'Tap + to capture your first note or checklist.'}</div>
    </div>;
  }
  const pinned = notes.filter(n => n.pinned); const rest = notes.filter(n => !n.pinned);
  const fmt = d => new Date(d + 'T00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  const Card = ({ n }) => {
    const checklist = (n.items || []).length > 0;
    const doneN = checklist ? n.items.filter(i => i.done).length : 0;
    return (
      <button className="tap" onClick={() => openNote(n)} style={{ width: '100%', textAlign: 'left', border: 'none', cursor: 'pointer', background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', padding: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          {n.pinned && <Icon name="flag" size={13} color="var(--orange)" fill weight={2} />}
          <div style={{ flex: 1, fontFamily: SF, fontSize: 16, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.3 }}>{n.title || 'New Note'}</div>
          {n.reminder && <Icon name="bell" size={14} color="var(--label3)" weight={2} />}
        </div>
        {checklist ? (
          <div style={{ marginTop: 7, display: 'flex', flexDirection: 'column', gap: 5 }}>
            {n.items.slice(0, 3).map((it, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Icon name={it.done ? 'checkmark.square.fill' : 'square'} size={16} color={it.done ? 'var(--accent)' : 'var(--label3)'} weight={1.8} />
                <span style={{ fontFamily: SF, fontSize: 14, color: it.done ? 'var(--label3)' : 'var(--label2)', textDecoration: it.done ? 'line-through' : 'none' }}>{it.text}</span>
              </div>
            ))}
            {n.items.length > 3 && <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--label3)', marginLeft: 24 }}>+{n.items.length - 3} more</span>}
            <span style={{ fontFamily: SF, fontSize: 12, color: 'var(--label3)', marginTop: 3 }}>{doneN}/{n.items.length} done · {fmt(n.date)}</span>
          </div>
        ) : (
          <>
            <div style={{ fontFamily: SF, fontSize: 14, color: 'var(--label2)', marginTop: 4, lineHeight: 1.4, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{n.body}</div>
            <div style={{ fontFamily: SF, fontSize: 12, color: 'var(--label3)', marginTop: 8 }}>{fmt(n.date)}</div>
          </>
        )}
      </button>
    );
  };
  return (
    <div style={{ padding: '0 16px' }}>
      {pinned.length > 0 && <>
        <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', padding: '0 16px 8px', textTransform: 'uppercase', letterSpacing: -0.08 }}>Pinned</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 22 }}>{pinned.map(n => <Card key={n.id} n={n} />)}</div>
      </>}
      {rest.length > 0 && <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', padding: '0 16px 8px', textTransform: 'uppercase', letterSpacing: -0.08 }}>All notes</div>}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{rest.map(n => <Card key={n.id} n={n} />)}</div>
    </div>
  );
}

function RemindersList({ reminders, toggle }) {
  const active = reminders.filter(r => !r.done); const done = reminders.filter(r => r.done);
  const fmt = (d) => {
    const dt = new Date(d + 'T00:00'); const diff = Math.round((dt - new Date(TODAY + 'T00:00')) / 86400000);
    const lbl = diff === 0 ? 'Today' : diff === 1 ? 'Tomorrow' : diff < 0 ? `${-diff}d ago` : dt.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
    return { lbl, overdue: diff < 0 };
  };
  const Item = ({ r, isLast }) => {
    const { lbl, overdue } = fmt(r.due);
    return (
      <Row isLast={isLast} accessory="none" height={52}
        iconNode={<button className="tap" onClick={() => toggle(r.id)} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 0, display: 'flex' }}>
          {r.done ? <Icon name="checkmark.circle.fill" size={24} color="var(--accent)" /> : <Icon name="circle" size={24} color="var(--label3)" weight={1.6} />}</button>}
        children={<div>
          <div style={{ fontFamily: SF, fontSize: 16, color: r.done ? 'var(--label3)' : 'var(--label)', letterSpacing: -0.3, textDecoration: r.done ? 'line-through' : 'none' }}>{r.title}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 2 }}>
            <Icon name="calendar" size={12} color={overdue && !r.done ? 'var(--red)' : 'var(--label2)'} weight={2} />
            <span style={{ fontFamily: SF, fontSize: 13, color: overdue && !r.done ? 'var(--red)' : 'var(--label2)' }}>{lbl}</span>
          </div></div>}
        value={r.flagged && !r.done ? <Icon name="flag" size={16} color="var(--orange)" fill weight={2} /> : null} />
    );
  };
  return (
    <div>
      <GroupedList header={`${active.length} remaining`}>{active.map((r, i) => <Item key={r.id} r={r} isLast={i === active.length - 1} />)}</GroupedList>
      {done.length > 0 && <GroupedList header="Completed">{done.map((r, i) => <Item key={r.id} r={r} isLast={i === done.length - 1} />)}</GroupedList>}
    </div>
  );
}

function CalendarTab() {
  const [sel, setSel] = useState(TODAY);
  const selEvents = CAL_EVENTS[sel] || [];
  return (
    <div style={{ padding: '0 16px' }}>
      <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', padding: 16, marginBottom: 18 }}>
        <MonthCalendar value={sel} onSelect={setSel} events={CAL_EVENTS} />
      </div>
      <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', padding: '0 16px 8px', textTransform: 'uppercase', letterSpacing: -0.08 }}>
        {new Date(sel + 'T00:00').toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })}</div>
      {selEvents.length ? (
        <GroupedList>{selEvents.map((e, i) => <Row key={i} isLast={i === selEvents.length - 1} accessory="none"
          iconNode={<span style={{ width: 4, height: 34, borderRadius: 2, background: e.color }} />} leftInset={16} title={e.title} subtitle="All day" />)}</GroupedList>
      ) : <div style={{ textAlign: 'center', padding: '24px', fontFamily: SF, fontSize: 15, color: 'var(--label3)' }}>No events</div>}
    </div>
  );
}

// ── Note editor (custom overlay: Done / title / bell + trash) ──
function NoteEditor({ open, note, onClose, onChange, onDelete, onOpenReminder }) {
  const [shown, setShown] = useState(false);
  const [mounted, setMounted] = useState(open);
  useEffect(() => {
    if (open) { setMounted(true); requestAnimationFrame(() => requestAnimationFrame(() => setShown(true))); }
    else { setShown(false); const t = setTimeout(() => setMounted(false), 300); return () => clearTimeout(t); }
  }, [open]);
  if (!mounted || !note) return null;
  const items = note.items || [];
  const upd = (patch) => onChange({ ...note, ...patch });
  const setItem = (i, patch) => upd({ items: items.map((it, k) => k === i ? { ...it, ...patch } : it) });
  const addItem = () => upd({ items: [...items, { text: '', done: false }] });
  const delItem = (i) => upd({ items: items.filter((_, k) => k !== i) });
  const fmtRem = note.reminder ? new Date(note.reminder + 'T00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : null;

  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 55, background: 'var(--bg)',
      transform: shown ? 'translateY(0)' : 'translateY(100%)', transition: 'transform .34s cubic-bezier(.32,.72,0,1)',
      display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <div style={{ paddingTop: STATUS_H, flexShrink: 0 }}>
        <div style={{ height: NAV_H, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 12px' }}>
          <NavButton prominent onClick={onClose}>Done</NavButton>
          <div style={{ flex: 1, textAlign: 'center', fontFamily: SF, fontSize: 17, fontWeight: 600, color: 'var(--label)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{note.title || 'New Note'}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <button className="tap" onClick={onOpenReminder} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 6, display: 'flex' }}>
              <Icon name={note.reminder ? 'bell.badge' : 'bell'} size={22} color={note.reminder ? 'var(--accent)' : 'var(--label)'} weight={2} /></button>
            <button className="tap" onClick={() => onDelete(note)} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 6, display: 'flex' }}>
              <Icon name="trash" size={21} color="var(--red)" weight={2} /></button>
          </div>
        </div>
      </div>
      <div className="noscroll" style={{ flex: 1, overflowY: 'auto', padding: '4px 18px 24px' }}>
        <input value={note.title} onChange={e => upd({ title: e.target.value })} placeholder="Title"
          style={{ width: '100%', border: 'none', background: 'none', outline: 'none', fontFamily: SF, fontSize: 28, fontWeight: 700, letterSpacing: -0.5, color: 'var(--label)', marginBottom: 6 }} />
        {fmtRem && (
          <button className="tap" onClick={onOpenReminder} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, border: 'none', cursor: 'pointer',
            background: 'color-mix(in srgb, var(--accent) 12%, transparent)', borderRadius: 8, padding: '5px 10px', marginBottom: 12 }}>
            <Icon name="bell" size={13} color="var(--accent)" fill weight={2} />
            <span style={{ fontFamily: SF, fontSize: 13, color: 'var(--accent)', fontWeight: 500 }}>{fmtRem}</span>
          </button>
        )}
        {items.length > 0 && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, marginBottom: 12 }}>
            {items.map((it, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '4px 0' }}>
                <button className="tap" onClick={() => setItem(i, { done: !it.done })} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 0, display: 'flex', flexShrink: 0 }}>
                  <Icon name={it.done ? 'checkmark.square.fill' : 'square'} size={22} color={it.done ? 'var(--accent)' : 'var(--label3)'} weight={1.8} /></button>
                <input value={it.text} onChange={e => setItem(i, { text: e.target.value })} placeholder="Item"
                  style={{ flex: 1, border: 'none', background: 'none', outline: 'none', fontFamily: SF, fontSize: 17, color: it.done ? 'var(--label3)' : 'var(--label)', textDecoration: it.done ? 'line-through' : 'none' }} />
                <button className="tap" onClick={() => delItem(i)} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4, display: 'flex' }}>
                  <Icon name="xmark.circle.fill" size={18} /></button>
              </div>
            ))}
          </div>
        )}
        <textarea value={note.body} onChange={e => upd({ body: e.target.value })} placeholder={items.length ? '' : 'Tap below to add a note or checklist item.'}
          rows={items.length ? 2 : 5} style={{ width: '100%', border: 'none', background: 'none', outline: 'none', resize: 'none', fontFamily: SF, fontSize: 17, lineHeight: 1.45, color: 'var(--label)', marginBottom: 14 }} />
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="tap" onClick={() => document.activeElement && document.activeElement.blur()} style={{ display: 'flex', alignItems: 'center', gap: 7, border: 'none', cursor: 'pointer', background: 'var(--fill3)', borderRadius: 10, padding: '9px 14px' }}>
            <Icon name="textformat" size={17} color="var(--accent)" weight={2} /><span style={{ fontFamily: SF, fontSize: 15, color: 'var(--accent)' }}>Add Text</span></button>
          <button className="tap" onClick={addItem} style={{ display: 'flex', alignItems: 'center', gap: 7, border: 'none', cursor: 'pointer', background: 'var(--fill3)', borderRadius: 10, padding: '9px 14px' }}>
            <Icon name="checklist" size={17} color="var(--accent)" weight={2} /><span style={{ fontFamily: SF, fontSize: 15, color: 'var(--accent)' }}>Add Item</span></button>
        </div>
        <GroupedList style={{ marginTop: 22 }}>
          <Row accessory={<Toggle value={note.pinned} onChange={v => upd({ pinned: v })} />}
            iconNode={<Icon name="flag" size={20} color="var(--orange)" fill weight={2} />} title="Pin to top" />
        </GroupedList>
      </div>
    </div>
  );
}

// ── Set Reminder sheet (mirrors the real app) ──
const ADV_ALERTS = ['None', '1 day before', '2 days before', '1 week before'];
const REPEATS = ['None', 'Daily', 'Weekly', 'Monthly', 'Yearly'];
function ReminderSheet({ open, value, onClose, onSave, onClear }) {
  const [allDay, setAllDay] = useState(true);
  const [date, setDate] = useState(value || TODAY);
  const [adv, setAdv] = useState(0);
  const [rep, setRep] = useState(0);
  const [showCal, setShowCal] = useState(false);
  useEffect(() => { if (open) { setDate(value || TODAY); setAdv(0); setRep(0); setShowCal(false); } }, [open, value]);
  const dLabel = new Date(date + 'T00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) + (allDay ? '' : ' at 12:00 AM');
  return (
    <Sheet open={open} onClose={onClose} title="Set Reminder"
      left={<NavButton onClick={onClose}>Cancel</NavButton>}
      right={<NavButton prominent onClick={() => onSave(date)}>Save</NavButton>}>
      <div style={{ paddingTop: 16 }}>
        <GroupedList>
          <Row accessory={<Toggle value={allDay} onChange={setAllDay} />} title="All Day" leftInset={16} />
        </GroupedList>
        <GroupedList>
          <Row accessory={<Icon name="chevron.down" size={15} color="var(--label3)" weight={2.4} style={{ transform: showCal ? 'rotate(180deg)' : 'none', transition: 'transform .25s' }} />}
            title="Date" value={<span style={{ color: showCal ? 'var(--accent)' : 'var(--label2)' }}>{dLabel}</span>} onClick={() => setShowCal(s => !s)} leftInset={16} />
          <div style={{ maxHeight: showCal ? 400 : 0, overflow: 'hidden', transition: 'max-height .32s cubic-bezier(.32,.72,0,1)' }}>
            <div style={{ padding: '8px 14px 14px' }}><MonthCalendar value={date} onSelect={setDate} /></div>
          </div>
        </GroupedList>
        <GroupedList header="Advance Alert">
          <Row title={ADV_ALERTS[adv]} leftInset={16}
            accessory={<Stepper onDec={() => setAdv(a => Math.max(0, a - 1))} onInc={() => setAdv(a => Math.min(ADV_ALERTS.length - 1, a + 1))} />} />
        </GroupedList>
        <GroupedList header="Repeat">
          <Row title="Repeat" leftInset={16}
            accessory={<button className="tap" onClick={() => setRep(r => (r + 1) % REPEATS.length)} style={{ border: 'none', background: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontFamily: SF, fontSize: 17, color: 'var(--accent)' }}>
              {REPEATS[rep]} <Icon name="chevron.down" size={14} color="var(--accent)" weight={2.4} /></button>} />
        </GroupedList>
        {value && <GroupedList><Row accessory="none" onClick={onClear} children={<div style={{ textAlign: 'center', fontFamily: SF, fontSize: 17, color: 'var(--red)' }}>Remove Reminder</div>} /></GroupedList>}
      </div>
    </Sheet>
  );
}

function Stepper({ onDec, onInc }) {
  return (
    <div style={{ display: 'flex', background: 'var(--fill3)', borderRadius: 8, overflow: 'hidden' }}>
      <button className="tap" onClick={onDec} style={{ border: 'none', background: 'none', cursor: 'pointer', width: 44, height: 30, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="minus" size={18} color="var(--label)" weight={2.4} /></button>
      <div style={{ width: 0.5, background: 'var(--sep)' }} />
      <button className="tap" onClick={onInc} style={{ border: 'none', background: 'none', cursor: 'pointer', width: 44, height: 30, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="plus" size={18} color="var(--label)" weight={2.4} /></button>
    </div>
  );
}

// ── Notifications route (bell): reminder alerts + budget alerts ──
function NotificationsScreen({ open, onClose, reminders, budgets, nav }) {
  const fmt = (d) => {
    const dt = new Date(d + 'T00:00'); const diff = Math.round((dt - new Date(TODAY + 'T00:00')) / 86400000);
    return diff === 0 ? 'Today' : diff === 1 ? 'Tomorrow' : diff < 0 ? `${-diff} day${diff === -1 ? '' : 's'} ago` : `in ${diff} days`;
  };
  const due = reminders.filter(r => !r.done).sort((a, b) => a.due.localeCompare(b.due));
  const overBudgets = budgets.filter(b => b.limit > 0 && b.spent > b.limit);
  const empty = due.length === 0 && overBudgets.length === 0;
  return (
    <PushView open={open} onClose={onClose} title="Notifications">
      <div style={{ fontFamily: SF, fontSize: 13, color: 'var(--label2)', padding: '0 32px 8px', lineHeight: 1.4 }}>
        Alerts come from your reminders and budgets. Push notifications aren’t enabled — these appear here in‑app.
      </div>
      {empty && <div style={{ textAlign: 'center', padding: '50px 30px' }}>
        <div style={{ display: 'inline-flex', width: 60, height: 60, borderRadius: 16, background: 'var(--fill3)', alignItems: 'center', justifyContent: 'center', marginBottom: 12 }}><Icon name="bell" size={32} color="var(--label3)" weight={1.8} /></div>
        <div style={{ fontFamily: SF, fontSize: 18, fontWeight: 600, color: 'var(--label)' }}>You’re all caught up</div></div>}
      {overBudgets.length > 0 && (
        <GroupedList header="Budgets">
          {overBudgets.map((b, i) => { const c = CAT[b.cat]; return (
            <Row key={b.cat} isLast={i === overBudgets.length - 1} onClick={() => { onClose(); nav('budgets'); }}
              iconNode={<IconTile icon="flag" color="var(--red)" size={30} />} title={`${c.name} over budget`}
              subtitle={`Spent ${money(b.spent, false)} of ${money(b.limit, false)}`} accessory="chevron" />
          ); })}
        </GroupedList>
      )}
      {due.length > 0 && (
        <GroupedList header="Reminders">
          {due.map((r, i) => { const overdue = r.due < TODAY; return (
            <Row key={r.id} isLast={i === due.length - 1} onClick={() => { onClose(); nav('notes', { sub: 'reminders' }); }}
              iconNode={<IconTile icon={overdue ? 'clock' : 'bell'} color={overdue ? 'var(--red)' : r.flagged ? 'var(--orange)' : 'var(--accent)'} size={30} />}
              title={r.title} subtitle={fmt(r.due)} titleColor={overdue ? 'var(--label)' : undefined} accessory="chevron" />
          ); })}
        </GroupedList>
      )}
    </PushView>
  );
}

Object.assign(window, { NotesScreen, NoteEditor, ReminderSheet, NotificationsScreen });
