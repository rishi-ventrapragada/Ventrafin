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
repo.txns = sample.map(([ago, description, amountPaise, over], i) => makeTxn(`demo-${i}`, { date: day(ago), description, amountPaise, ...over }))

const auth = fakeAuth({ id: 'demo', email: 'demo@example.com', name: 'Demo' })
const context = createAppContext({ repo, auth, prefs: createMemoryEntryPrefs({ accountId: 'acc-cash', method: 'upi' }) })
const app = createApp(App)
installUi(app)
app.provide(APP_CONTEXT, context)
app.use(createAppRouter(auth, createWebHashHistory()))
app.mount('#app')
