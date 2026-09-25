import { watch } from 'vue'
import { createRouter, type RouterHistory } from 'vue-router'
import AppShell from './components/AppShell.vue'
import { safeNextPath, type AuthService } from './data/auth'

declare module 'vue-router' {
  interface RouteMeta {
    /** Reachable without signing in. */
    public?: boolean
    title?: string
  }
}

/**
 * One route per section (DECISIONS.md D8). Every route except /login,
 * /auth/callback and the not-found page needs a signed-in user; the guard
 * sends everyone else to /login and brings them back afterwards.
 */
export function createAppRouter(auth: AuthService, history: RouterHistory) {
  const router = createRouter({
    history,
    routes: [
      { path: '/login', name: 'login', component: () => import('./pages/LoginPage.vue'), meta: { public: true, title: 'Sign in' } },
      {
        path: '/auth/callback',
        name: 'auth-callback',
        component: () => import('./pages/AuthCallbackPage.vue'),
        meta: { public: true, title: 'Signing in' },
      },
      {
        path: '/',
        component: AppShell,
        children: [
          { path: '', redirect: '/dashboard' },
          { path: 'dashboard', name: 'dashboard', component: () => import('./pages/DashboardPage.vue'), meta: { title: 'Dashboard' } },
          {
            path: 'transactions',
            name: 'transactions',
            component: () => import('./pages/TransactionsPage.vue'),
            meta: { title: 'Transactions' },
          },
          { path: 'add', name: 'add', component: () => import('./pages/AddPage.vue'), meta: { title: 'Add' } },
          { path: 'categories', name: 'categories', component: () => import('./pages/CategoriesPage.vue'), meta: { title: 'Categories' } },
          { path: 'accounts', name: 'accounts', component: () => import('./pages/AccountsPage.vue'), meta: { title: 'Accounts' } },
          { path: 'bills', name: 'bills', component: () => import('./pages/BillsPage.vue'), meta: { title: 'Bills' } },
          { path: 'reports', name: 'reports', component: () => import('./pages/ReportsPage.vue'), meta: { title: 'Reports' } },
          { path: 'settings', name: 'settings', component: () => import('./pages/SettingsPage.vue'), meta: { title: 'Settings' } },
        ],
      },
      {
        path: '/:pathMatch(.*)*',
        name: 'not-found',
        component: () => import('./pages/NotFoundPage.vue'),
        meta: { public: true, title: 'Not found' },
      },
    ],
  })

  router.beforeEach(async (to) => {
    await auth.ready
    const signedIn = auth.user.value !== null
    if (to.name === 'login' && signedIn) return safeNextPath(to.query.next) ?? '/dashboard'
    if (to.meta.public) return true
    if (!signedIn) return { name: 'login', query: to.fullPath === '/' || to.fullPath === '/dashboard' ? {} : { next: to.fullPath } }
    return true
  })

  router.afterEach((to) => {
    document.title = to.meta.title ? `${to.meta.title} · Ventrafin` : 'Ventrafin'
  })

  // Signed out (here, in another tab, or the session expired): back to the login page.
  watch(auth.user, (user) => {
    if (!user && !router.currentRoute.value.meta.public) void router.replace({ name: 'login' })
  })

  return router
}
