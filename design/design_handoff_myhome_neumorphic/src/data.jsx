// data.jsx — MyHome sample data (India: ₹, real merchants, bank accounts).
// Budget state ('under' | 'over') adds discretionary spend so categories blow limits.

const CATEGORIES = [
  { id: 'groceries',     name: 'Groceries',       icon: 'cart',        color: CAT_COLORS.groceries },
  { id: 'dining',        name: 'Dining',          icon: 'fork.knife',  color: CAT_COLORS.dining },
  { id: 'fuel',          name: 'Fuel',            icon: 'fuelpump',    color: CAT_COLORS.fuel },
  { id: 'utilities',     name: 'Utilities',       icon: 'bolt',        color: CAT_COLORS.utilities },
  { id: 'rent',          name: 'Rent',            icon: 'house.cat',   color: CAT_COLORS.rent },
  { id: 'auto',          name: 'Auto/Cab',        icon: 'car',         color: CAT_COLORS.auto },
  { id: 'shopping',      name: 'Shopping',        icon: 'bag',         color: CAT_COLORS.shopping },
  { id: 'health',        name: 'Health/Pharmacy', icon: 'medicalbag',  color: CAT_COLORS.health },
  { id: 'subscriptions', name: 'Subscriptions',   icon: 'repeat',      color: CAT_COLORS.subscriptions },
  { id: 'entertainment', name: 'Entertainment',   icon: 'tv',          color: CAT_COLORS.entertainment },
  { id: 'other',         name: 'Other',           icon: 'other',       color: CAT_COLORS.other },
];
const CAT = Object.fromEntries(CATEGORIES.map(c => [c.id, c]));

// Bank accounts (source of an expense)
const ACCOUNTS = [
  { id: 'hdfc1329', label: 'HDFC ••1329', kind: 'Savings' },
  { id: 'icici5005', label: 'ICICI CC ••5005', kind: 'Credit Card' },
  { id: 'hdfc2758', label: 'HDFC ••2758', kind: 'Savings' },
];

// ₹ with Indian digit grouping
function money(n, cents = true) {
  const v = Math.abs(n).toLocaleString('en-IN', {
    minimumFractionDigits: cents ? 2 : 0, maximumFractionDigits: cents ? 2 : 0,
  });
  return (n < 0 ? '-₹' : '₹') + v;
}

// Expenses for June 2026. Mirrors the real app's data; `over` adds more.
function buildExpenses(over) {
  const base = [
    { id: 'e1',  merchant: 'SRI SAI VEG BASKET',       cat: 'groceries', amount: 452.00,  date: '2026-06-03', account: 'HDFC ••1329',    note: '', source: 'gmail' },
    { id: 'e2',  merchant: 'Amazon',                   cat: 'shopping',  amount: 308.00,  date: '2026-06-03', account: 'HDFC ••1329',    note: 'Order #402-77', source: 'gmail' },
    { id: 'e3',  merchant: 'Amazon',                   cat: 'shopping',  amount: 833.00,  date: '2026-06-02', account: 'ICICI CC ••5005', note: '', source: 'gmail' },
    { id: 'e4',  merchant: 'FRESHALICIOUS SUPERMART',  cat: 'groceries', amount: 1500.00, date: '2026-06-02', account: 'HDFC ••1329',    note: 'Monthly stock-up', source: 'gmail' },
    { id: 'e5',  merchant: 'Delightful Gourmet Pvt',   cat: 'dining',    amount: 537.00,  date: '2026-06-01', account: 'HDFC ••2758',    note: 'Team lunch', source: 'gmail' },
    { id: 'e6',  merchant: 'BigBasket',                cat: 'groceries', amount: 153.98,  date: '2026-06-01', account: 'HDFC ••1329',    note: '', source: 'gmail' },
  ];
  if (over) base.push(
    { id: 'e7',  merchant: 'Indian Oil',         cat: 'fuel',          amount: 2400.00, date: '2026-06-03', account: 'HDFC ••1329',    note: 'Full tank', source: 'gmail' },
    { id: 'e8',  merchant: 'Croma',              cat: 'shopping',      amount: 4990.00, date: '2026-06-03', account: 'ICICI CC ••5005', note: 'Headphones', source: 'gmail' },
    { id: 'e9',  merchant: 'Swiggy',             cat: 'dining',        amount: 642.00,  date: '2026-06-02', account: 'HDFC ••2758',    note: 'Dinner', source: 'gmail' },
    { id: 'e10', merchant: 'Zomato',             cat: 'dining',        amount: 1180.00, date: '2026-06-02', account: 'ICICI CC ••5005', note: '', source: 'manual' },
    { id: 'e11', merchant: 'Uber',               cat: 'auto',          amount: 318.00,  date: '2026-06-01', account: 'HDFC ••1329',    note: 'Airport drop', source: 'gmail' },
  );
  return base.map(e => ({ ...e, type: 'expense' })).sort((a, b) => b.date.localeCompare(a.date) || a.merchant.localeCompare(b.merchant));
}

// ── Income categories (positive / green) ──
const INCOME_CATS = [
  { id: 'salary',    name: 'Salary',     icon: 'briefcase',       color: '#00F5A0' },
  { id: 'freelance', name: 'Freelance',  icon: 'sparkles',        color: '#2DD4BF' },
  { id: 'refund',    name: 'Refund',     icon: 'arrow.clockwise', color: '#22D3EE' },
  { id: 'interest',  name: 'Interest',   icon: 'bolt',            color: '#5EEAD4' },
  { id: 'transfer',  name: 'Transfer in', icon: 'arrow.down.left', color: '#38BDF8' },
];
const INCOME_CAT = Object.fromEntries(INCOME_CATS.map(c => [c.id, c]));

// Income for June 2026 (credits into accounts).
function buildIncome() {
  const base = [
    { id: 'i1', merchant: 'Acme Corp · Payroll', cat: 'salary',    amount: 85000.00, date: '2026-06-01', account: 'HDFC ••1329', note: 'June salary' },
    { id: 'i2', merchant: 'Savings interest',     cat: 'interest',  amount: 312.40,   date: '2026-06-01', account: 'HDFC ••1329', note: '' },
    { id: 'i3', merchant: 'UPI · Design retainer', cat: 'freelance', amount: 6500.00,  date: '2026-06-02', account: 'HDFC ••1329', note: 'Studio Mango' },
    { id: 'i4', merchant: 'Amazon refund',         cat: 'refund',    amount: 833.00,   date: '2026-06-03', account: 'ICICI CC ••5005', note: 'Returned item' },
  ];
  return base.map(e => ({ ...e, type: 'income' })).sort((a, b) => b.date.localeCompare(a.date) || a.merchant.localeCompare(b.merchant));
}

// Monthly budget limits (₹). 0 = no budget set (mirrors real app empty state).
function defaultLimits(over) {
  if (over) return { groceries: 1800, dining: 800, fuel: 2000, shopping: 1000, utilities: 0, rent: 0, auto: 0, health: 0, subscriptions: 0, entertainment: 0 };
  return { groceries: 2500, dining: 2000, shopping: 1200, fuel: 0, utilities: 0, rent: 0, auto: 0, health: 0, subscriptions: 0, entertainment: 0 };
}

// Gmail Review Inbox — auto-detected charges awaiting confirmation.
const REVIEW_INBOX = [
  { id: 'r1', merchant: 'Reliance Smart',  amount: 1284.50, guessCat: 'groceries', date: '2026-06-03', account: 'HDFC ••1329',    subject: 'Your Reliance Smart eBill', from: 'ebill@reliancesmart.in' },
  { id: 'r2', merchant: 'HP Petrol Pump',  amount: 2000.00, guessCat: 'fuel',      date: '2026-06-03', account: 'ICICI CC ••5005', subject: 'Transaction Alert: ₹2000 spent', from: 'alerts@icicibank.com' },
  { id: 'r3', merchant: 'Apollo Pharmacy', amount: 460.00,  guessCat: 'health',    date: '2026-06-02', account: 'HDFC ••1329',    subject: 'Apollo 24|7 — Order delivered', from: 'orders@apollo247.com' },
  { id: 'r4', merchant: 'Netflix',         amount: 649.00,  guessCat: 'subscriptions', date: '2026-06-02', account: 'ICICI CC ••5005', subject: 'Your Netflix payment receipt', from: 'info@account.netflix.com' },
];

// Notes — text notes + checklists (items). reminder = ISO date or null.
const NOTES = [
  { id: 'n1', title: 'Grocery list', items: [
      { text: 'Toor dal 1kg', done: true }, { text: 'Milk (2L)', done: false },
      { text: 'Atta 5kg', done: false }, { text: 'Coffee', done: false }, { text: 'Dish soap', done: false }],
    body: '', date: '2026-06-02', pinned: true, reminder: '2026-06-04' },
  { id: 'n2', title: 'Home maintenance', items: [], body: 'Replace water purifier filter (every 90 days). Last changed in March. Book AC service before summer peak.', date: '2026-05-30', pinned: true, reminder: null },
  { id: 'n3', title: 'Trip budget — Goa', items: [], body: 'Target ₹40,000 for the August trip. Flights ~15k, stay ~16k, food + activities ~9k.', date: '2026-05-28', pinned: false, reminder: null },
  { id: 'n4', title: 'Wifi password', items: [], body: 'Guest network: MapleSt-Guest / sunflower-42', date: '2026-05-21', pinned: false, reminder: null },
];

const REMINDERS = [
  { id: 'rm1', title: 'Pay electricity bill (BESCOM)', due: '2026-06-04', done: false, flagged: true },
  { id: 'rm2', title: 'Renew two-wheeler insurance', due: '2026-06-08', done: false, flagged: false },
  { id: 'rm3', title: 'Review monthly budget', due: '2026-06-30', done: false, flagged: false },
  { id: 'rm4', title: 'Cancel free trial — Audible', due: '2026-06-02', done: false, flagged: true },
  { id: 'rm5', title: 'Submit reimbursement', due: '2026-05-29', done: true, flagged: false },
];

// Calendar events (date -> dots / titles)
const CAL_EVENTS = {
  '2026-06-04': [{ title: 'Electricity bill due', color: 'var(--red)' }, { title: 'Grocery list reminder', color: CAT_COLORS.groceries }],
  '2026-06-08': [{ title: 'Two-wheeler insurance', color: 'var(--orange)' }],
  '2026-06-14': [{ title: 'BigBasket monthly order', color: CAT_COLORS.groceries }],
  '2026-06-20': [{ title: 'Dinner out', color: CAT_COLORS.dining }],
  '2026-06-30': [{ title: 'Budget review', color: 'var(--accent)' }],
};

const PROFILE = { name: 'Nobel Reo Jacob', email: 'nobelreojacob@gmail.com', initials: 'NJ' };
const TODAY = '2026-06-03';

Object.assign(window, {
  CATEGORIES, CAT, ACCOUNTS, money, buildExpenses, defaultLimits,
  INCOME_CATS, INCOME_CAT, buildIncome,
  REVIEW_INBOX, NOTES, REMINDERS, CAL_EVENTS, PROFILE, TODAY,
});
