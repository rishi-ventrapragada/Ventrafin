import './style.css'
import { createApp } from 'vue'
import { createWebHistory } from 'vue-router'
import App from './App.vue'
import { APP_CONTEXT, createAppContext } from './data/appContext'
import { createSupabaseAuth } from './data/auth'
import { createLocalEntryPrefs } from './data/entryPrefs'
import { createSupabasePasskeys } from './data/passkeys'
import { createSupabase, readConfig } from './data/supabaseClient'
import { SupabaseFinanceRepository } from './data/supabaseRepository'
import SetupNeededPage from './pages/SetupNeededPage.vue'
import { createAppRouter } from './router'
import { installUi } from './ui'

const config = readConfig()

if ('problem' in config) {
  // Built without its Supabase settings: say so instead of a blank page.
  const app = createApp(SetupNeededPage, { problem: config.problem })
  installUi(app)
  app.mount('#app')
} else {
  const client = createSupabase(config)
  const auth = createSupabaseAuth(client)
  const context = createAppContext({
    repo: new SupabaseFinanceRepository(client),
    auth,
    passkeys: createSupabasePasskeys(client, config),
    prefs: createLocalEntryPrefs(),
  })
  const app = createApp(App)
  installUi(app)
  app.provide(APP_CONTEXT, context)
  app.use(createAppRouter(auth, createWebHistory()))
  app.mount('#app')
}
