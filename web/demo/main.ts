// DEV-ONLY demo: the real app on the in-memory fake repository with made-up
// sample data, signed in as a fake user. For looking at the UI (and taking
// screenshots) without Google sign-in or touching real data. Served by
// `npm run dev` at http://localhost:5173/demo.html; it is not part of
// `npm run build` (only index.html is), so it never reaches Vercel.
import '../src/style.css'
import { createApp } from 'vue'
import { createWebHashHistory } from 'vue-router'
import App from '../src/App.vue'
import { APP_CONTEXT, createAppContext } from '../src/data/appContext'
import { createMemoryEntryPrefs } from '../src/data/entryPrefs'
import { addDays, indiaToday } from '../src/lib/dates'
import type { Txn } from '../src/lib/models'
import { createAppRouter } from '../src/router'
import { installUi } from '../src/ui'
import { FakeRepository, makeTxn } from '../tests/support/fakeRepository'
import { fakeAuth } from '../tests/support/mountApp'

const today = indiaToday()
const day = (n: number) => addDays(today, -n)

// Made-up sample entries (not anyone's data).
const sample: [number, string, number, Partial<Txn>][] = [
  [0, 'Swiggy dinner', 45000, { categoryId: 'cat-food', autoCategorized: true }],
  [0, 'DMart Andheri', 234050, { categoryId: 'cat-groc', autoCategorized: true, paymentMethod: 'card', accountId: 'acc-cc' }],
  [1, 'MSEDCL electricity bill Sept', 184000, { categoryId: 'cat-elec', autoCategorized: true, accountId: 'acc-bank', paymentMethod: 'debit' }],
  [1, 'Ramesh kirana store', 62000, { categoryId: null, paymentMethod: 'cash' }],
  [2, 'Apollo Pharmacy', 38000, { categoryId: 'cat-med', autoCategorized: true }],
  [3, 'ATM withdrawal', 500000, { type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null, paymentMethod: null }],
  [4, 'Zomato lunch', 32000, { categoryId: 'cat-food', autoCategorized: true }],
  [5, 'Salary September', 8500000, { type: 'income', categoryId: 'cat-salary', autoCategorized: true, accountId: 'acc-bank', paymentMethod: null }],
  [6, 'Milk and bread', 9000, { categoryId: 'cat-groc', paymentMethod: 'cash' }],
  [8, 'Gift for Meena', 150000, { categoryId: null, paymentMethod: 'upi' }],
  [10, 'Chai', 2000, { categoryId: 'cat-food', paymentMethod: 'cash' }],
  [30, 'Swiggy', 52000, { categoryId: 'cat-food', autoCategorized: true }],
  [32, 'BigBasket', 310000, { categoryId: 'cat-groc', autoCategorized: true }],
  [35, 'Dr. Mehta clinic', 80000, { categoryId: 'cat-med' }],
]

const repo = new FakeRepository()
repo.delay = 150
repo.liveReports = true
// demo.html?theme=marigold opens in another theme (the profile's theme).
repo.profile.theme = new URLSearchParams(location.search).get('theme') ?? 'ocean'
repo.txns = sample.map(([ago, description, amountPaise, over], i) => makeTxn(`demo-${i}`, { date: day(ago), description, amountPaise, ...over }))

// A year of made-up history for the Reports trends: a salary and a spread of
// spending each month, varying a little.
for (let back = 1; back <= 12; back++) {
  const ago = back * 30 + 5
  const wobble = 1 + ((back * 37) % 11) / 20
  const history: [string, number, Partial<Txn>][] = [
    ['Salary', 8500000, { type: 'income', categoryId: 'cat-salary', accountId: 'acc-bank', paymentMethod: null }],
    ['DMart', Math.round(900000 * wobble), { categoryId: 'cat-groc' }],
    ['Swiggy', Math.round(420000 * wobble), { categoryId: 'cat-food' }],
    ['MSEDCL', Math.round(160000 + back * 9000), { categoryId: 'cat-elec', accountId: 'acc-bank' }],
    ['Apollo', back % 3 === 0 ? 260000 : 40000, { categoryId: 'cat-med' }],
    ['Misc', Math.round(120000 * wobble), { categoryId: null }],
  ]
  history.forEach(([description, amountPaise, over], i) =>
    repo.txns.push(makeTxn(`hist-${back}-${i}`, { date: day(ago + i), description, amountPaise, ...over })),
  )
}

const inDays = (n: number) => addDays(today, n)
const monthOfIso = (iso: string) => ({ year: Number(iso.slice(0, 4)), month: Number(iso.slice(5, 7)) })
repo.bills = [
  { id: 'demo-b1', name: 'MSEDCL electricity', kind: 'utility', amountPaise: 184000, dueDay: 12, accountId: 'acc-bank', categoryId: 'cat-elec', reminderEnabled: true, paidThroughMonth: monthOfIso(inDays(-40)), nextDueDate: inDays(-3), daysUntil: -3, status: 'overdue', overdueCount: 1 },
  { id: 'demo-b2', name: 'Airtel broadband', kind: 'utility', amountPaise: 99900, dueDay: 28, accountId: 'acc-cc', categoryId: null, reminderEnabled: true, paidThroughMonth: monthOfIso(inDays(-30)), nextDueDate: inDays(2), daysUntil: 2, status: 'due_soon', overdueCount: 0 },
  { id: 'demo-b3', name: 'Home loan EMI', kind: 'emi', amountPaise: 2450000, dueDay: 5, accountId: 'acc-bank', categoryId: null, reminderEnabled: false, paidThroughMonth: monthOfIso(today), nextDueDate: inDays(12), daysUntil: 12, status: 'upcoming', overdueCount: 0 },
]

const auth = fakeAuth({ id: 'demo', email: 'demo@example.com', name: 'Demo' })
const context = createAppContext({ repo, auth, prefs: createMemoryEntryPrefs({ accountId: 'acc-cash', method: 'upi' }) })
const app = createApp(App)
installUi(app)
app.provide(APP_CONTEXT, context)
app.use(createAppRouter(auth, createWebHashHistory()))
app.mount('#app')
