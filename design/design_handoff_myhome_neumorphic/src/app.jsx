// app.jsx — MyHome shell: Liquid UI theme, plasma field, state, nav, sheets, tweaks.
const { useState: uS, useEffect: uE, useMemo: uM } = React;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "style": "neuro",
  "accent": "Amber",
  "blob": "Nebula",
  "motion": "alive",
  "numberRoll": true,
  "glassBlur": 24,
  "glassAlpha": 1,
  "dataState": "under"
}/*EDITMODE-END*/;

const TABS = [
  { id: 'home',     label: 'Home',     icon: 'house' },
  { id: 'expenses', label: 'Activity', icon: 'creditcard' },
  { id: 'budgets',  label: 'Budgets',  icon: 'chart.pie' },
  { id: 'notes',    label: 'Notes',    icon: 'note' },
  { id: 'settings', label: 'Settings', icon: 'gear' },
];
const BUDGET_CATS = CATEGORIES.filter(c => c.id !== 'other').map(c => c.id);

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const over = t.dataState === 'over';
  const pair = ACCENT_PAIRS[t.accent] || ACCENT_PAIRS.Amber;
  const meta = STYLE_META[t.style] || STYLE_META.liquid;
  const light = meta.light;
  const plasma = meta.plasma;
  const palette = BLOB_PALETTES[t.blob] || BLOB_PALETTES.Nebula;
  const themeVars = uM(() => buildThemeVars({ style: t.style, pair, blur: t.glassBlur, alpha: t.glassAlpha }),
    [t.style, t.accent, t.glassBlur, t.glassAlpha]);

  uE(() => { installRipple(); }, []);

  // ── app state ──
  const [tab, setTab] = uS('home');
  const [expenses, setExpenses] = uS(() => buildExpenses(over));
  const [income] = uS(() => buildIncome());
  const [review, setReview] = uS(() => REVIEW_INBOX.slice());
  const [reminders, setReminders] = uS(() => REMINDERS.map(r => ({ ...r })));
  const [notes, setNotes] = uS(() => NOTES.map(n => ({ ...n })));
  const [limits, setLimits] = uS(() => defaultLimits(over));
  const [faceID, setFaceID] = uS(false);
  const [gmailOn, setGmailOn] = uS(true);
  const [syncDays, setSyncDays] = uS(120);
  const [syncing, setSyncing] = uS(false);
  const [lastSynced, setLastSynced] = uS('7 hours ago');
  const [expenseSub, setExpenseSub] = uS('all');
  const [notesSub, setNotesSub] = uS('notes');

  // sheets / overlays
  const [addOpen, setAddOpen] = uS(false);
  const [editing, setEditing] = uS(null);
  const [editingBudget, setEditingBudget] = uS(null);
  const [noteId, setNoteId] = uS(null);
  const [reminderOpen, setReminderOpen] = uS(false);
  const [notifOpen, setNotifOpen] = uS(false);
  const [analyticsOpen, setAnalyticsOpen] = uS(false);

  // rebuild sample data when data-state tweak flips
  uE(() => { setExpenses(buildExpenses(over)); setReview(REVIEW_INBOX.slice()); setLimits(defaultLimits(over)); }, [over]);

  const spentBy = uM(() => {
    const m = {}; expenses.forEach(e => { m[e.cat] = (m[e.cat] || 0) + e.amount; }); return m;
  }, [expenses]);
  const budgets = uM(() => BUDGET_CATS.map(cat => ({ cat, limit: limits[cat] || 0, spent: Math.round((spentBy[cat] || 0) * 100) / 100 })), [limits, spentBy]);

  // ── actions ──
  const nav = (target, opts = {}) => {
    setNotifOpen(false);
    setTab(target);
    if (target === 'expenses' && opts.review) setExpenseSub('review');
    if (target === 'notes' && opts.sub) setNotesSub(opts.sub);
  };
  const openExpense = (e) => { setEditing(e); setAddOpen(true); };
  const openAdd = () => { setEditing(null); setAddOpen(true); };
  const saveExpense = (e) => {
    setExpenses(prev => {
      const i = prev.findIndex(x => x.id === e.id);
      const next = i >= 0 ? prev.map(x => x.id === e.id ? e : x) : [e, ...prev];
      return next.sort((a, b) => b.date.localeCompare(a.date) || a.merchant.localeCompare(b.merchant));
    });
    setAddOpen(false);
  };
  const deleteExpense = (e) => { setExpenses(prev => prev.filter(x => x.id !== e.id)); setAddOpen(false); };
  const confirmReview = (item, cat) => {
    const e = { id: 'x' + Date.now(), merchant: item.merchant, cat, account: item.account, amount: item.amount, date: item.date, note: '', source: 'gmail', type: 'expense' };
    setExpenses(prev => [e, ...prev].sort((a, b) => b.date.localeCompare(a.date) || a.merchant.localeCompare(b.merchant)));
    setReview(prev => prev.filter(r => r.id !== item.id));
  };
  const dismissReview = (item) => setReview(prev => prev.filter(r => r.id !== item.id));
  const toggleReminder = (id) => setReminders(prev => prev.map(r => r.id === id ? { ...r, done: !r.done } : r));

  // budgets
  const onEditBudget = (cat) => setEditingBudget(cat);
  const saveBudget = (cat, val) => { setLimits(prev => ({ ...prev, [cat]: val })); setEditingBudget(null); };
  const clearBudget = (cat) => { setLimits(prev => ({ ...prev, [cat]: 0 })); setEditingBudget(null); };

  // notes
  const currentNote = notes.find(n => n.id === noteId) || null;
  const openNote = (n) => setNoteId(n.id);
  const openNewNote = () => {
    const n = { id: 'note' + Date.now(), title: '', body: '', items: [], pinned: false, date: TODAY, reminder: null };
    setNotes(prev => [n, ...prev]); setNoteId(n.id);
  };
  const changeNote = (n) => setNotes(prev => prev.map(x => x.id === n.id ? n : x));
  const closeNote = () => {
    setNotes(prev => prev.filter(n => n.id !== noteId || (n.title.trim() || (n.body || '').trim() || (n.items || []).some(i => i.text.trim()))));
    setNoteId(null);
  };
  const deleteNote = (n) => { setNotes(prev => prev.filter(x => x.id !== n.id)); setNoteId(null); };
  const saveNoteReminder = (date) => { if (currentNote) changeNote({ ...currentNote, reminder: date }); setReminderOpen(false); };
  const clearNoteReminder = () => { if (currentNote) changeNote({ ...currentNote, reminder: null }); setReminderOpen(false); };

  // sync
  const onSyncNow = () => {
    if (syncing) return;
    setSyncing(true);
    setTimeout(() => { setSyncing(false); setLastSynced('Just now'); }, 1400);
  };

  const ctx = {
    expenses, income, budgets, review, reminders, notes, over,
    reviewCount: review.length, accentName: t.accent,
    nav, openExpense, openAdd, confirmReview, dismissReview, toggleReminder,
    onEditBudget, openNote, openNewNote,
    faceID, setFaceID, gmailOn, setGmailOn, syncDays, setSyncDays, lastSynced, onSyncNow, syncing,
    expenseSub, setExpenseSub, notesSub, setNotesSub,
    openNotifications: () => setNotifOpen(true),
    openAnalytics: () => setAnalyticsOpen(true),
    style: t.style,
  };

  // scale-to-fit stage
  const [scale, setScale] = uS(1);
  uE(() => {
    const W = 402, H = 874;
    const fit = () => setScale(Math.min((window.innerWidth - 24) / W, (window.innerHeight - 24) / H, 1.4));
    fit(); window.addEventListener('resize', fit); return () => window.removeEventListener('resize', fit);
  }, []);

  const screen = {
    home: <HomeScreen ctx={ctx} />, expenses: <ExpensesScreen ctx={ctx} />,
    budgets: <BudgetsScreen ctx={ctx} />, notes: <NotesScreen ctx={ctx} />,
    settings: <SettingsScreen ctx={ctx} />,
  }[tab];

  const ebCat = editingBudget ? budgets.find(b => b.cat === editingBudget) : null;

  return (
    <RollCtx.Provider value={!!t.numberRoll}>
    <div style={{ ...themeVars, position: 'fixed', inset: 0, background: light ? '#E7E3D8' : '#020308',
      display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
      <div style={{ transform: `scale(${scale})`, transformOrigin: 'center' }}>
        <IOSDevice dark={!light}>
          <div style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
            {plasma
              ? <PlasmaField palette={palette} intensity={t.motion} theme={light ? 'frosted' : 'void'} />
              : <div style={{ position: 'absolute', inset: 0, background: 'var(--bg)', zIndex: 0 }}>
                  <div style={{ position: 'absolute', inset: 0, background: 'var(--ambient)', pointerEvents: 'none' }} />
                </div>}
            {screen}
            <TabBar tabs={TABS} active={tab} onChange={setTab} />

            <AddExpenseSheet open={addOpen} editing={editing} onClose={() => setAddOpen(false)} onSave={saveExpense} onDelete={deleteExpense} />
            <BudgetEditSheet open={!!editingBudget} cat={editingBudget} currentLimit={ebCat ? ebCat.limit : 0} spent={ebCat ? ebCat.spent : 0}
              onClose={() => setEditingBudget(null)} onSave={saveBudget} onClear={clearBudget} />
            <NoteEditor open={!!noteId} note={currentNote} onClose={closeNote} onChange={changeNote} onDelete={deleteNote} onOpenReminder={() => setReminderOpen(true)} />
            <ReminderSheet open={reminderOpen} value={currentNote ? currentNote.reminder : null} onClose={() => setReminderOpen(false)} onSave={saveNoteReminder} onClear={clearNoteReminder} />
            <NotificationsScreen open={notifOpen} onClose={() => setNotifOpen(false)} reminders={reminders} budgets={budgets} nav={nav} />
            <AnalyticsScreen open={analyticsOpen} onClose={() => setAnalyticsOpen(false)} palette={palette} plasma={plasma} />
          </div>
        </IOSDevice>
      </div>

      <TweaksPanel>
        <TweakSection label="Interface" />
        <TweakSelect label="UI style" value={t.style}
          options={STYLE_ORDER.map(s => ({ value: s, label: STYLE_META[s].label }))}
          onChange={v => setTweak('style', v)} />
        <TweakColor label="Accent" value={[pair.pos, pair.neg, pair.glow]}
          options={Object.values(ACCENT_PAIRS).map(p => [p.pos, p.neg, p.glow])}
          onChange={arr => { const name = Object.keys(ACCENT_PAIRS).find(k => ACCENT_PAIRS[k].pos === arr[0]); if (name) setTweak('accent', name); }} />
        {plasma && <>
          <TweakSection label="Atmosphere" />
          <TweakColor label="Plasma" value={palette}
            options={Object.values(BLOB_PALETTES)}
            onChange={arr => { const name = Object.keys(BLOB_PALETTES).find(k => BLOB_PALETTES[k][0] === arr[0]); if (name) setTweak('blob', name); }} />
          <TweakRadio label="Motion" value={t.motion} options={[{ value: 'calm', label: 'Calm' }, { value: 'balanced', label: 'Mid' }, { value: 'alive', label: 'Alive' }]} onChange={v => setTweak('motion', v)} />
        </>}
        <TweakSection label="Material" />
        <TweakSlider label="Glass blur" value={t.glassBlur} min={8} max={40} step={2} unit="px" onChange={v => setTweak('glassBlur', v)} />
        <TweakSlider label="Glass tint" value={t.glassAlpha} min={0.5} max={2} step={0.1} onChange={v => setTweak('glassAlpha', v)} />
        <TweakSection label="Behaviour" />
        <TweakToggle label="Number-roll" value={t.numberRoll} onChange={v => setTweak('numberRoll', v)} />
        <TweakSection label="Sample data" />
        <TweakRadio label="Budget state" value={t.dataState} options={[{ value: 'under', label: 'Under' }, { value: 'over', label: 'Over' }]} onChange={v => setTweak('dataState', v)} />
      </TweaksPanel>
    </div>
    </RollCtx.Provider>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
