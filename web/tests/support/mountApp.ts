// Mounts real pages (PrimeVue, router, toasts, confirm dialogs) on top of
// the fake repository, a signed-in fake user and a fixed India clock.
import { flushPromises, mount } from '@vue/test-utils'
import ConfirmDialog from 'primevue/confirmdialog'
import Toast from 'primevue/toast'
import { defineComponent, h, ref, shallowRef } from 'vue'
import { createMemoryHistory, RouterView } from 'vue-router'
import { APP_CONTEXT, createAppContext, type AppContext } from '@/data/appContext'
import type { AppUser, AuthService } from '@/data/auth'
import { createMemoryEntryPrefs, type EntryPrefs } from '@/data/entryPrefs'
import type { PasskeyService } from '@/data/passkeys'
import { createAppRouter } from '@/router'
import { installUi } from '@/ui'
import { FakeRepository, fixedClock } from './fakeRepository'

export function fakeAuth(user: AppUser | null = { id: 'user-1', email: 'dad@example.com', name: 'Dad' }): AuthService {
  const u = shallowRef<AppUser | null>(user)
  return {
    user: u,
    ready: Promise.resolve(),
    async signInWithGoogle() {},
    async signOut() {
      u.value = null
    },
  }
}

export interface MountOptions {
  repo?: FakeRepository
  online?: boolean
  prefs?: EntryPrefs
  /** The route to open, e.g. '/add'. */
  path: string
  signedIn?: boolean
  /** Subscribe to the fake repository's change feed (like Supabase Realtime). */
  realtime?: boolean
  passkeys?: PasskeyService
}

export async function mountApp({
  repo = new FakeRepository(),
  online = true,
  prefs = createMemoryEntryPrefs(),
  path,
  signedIn = true,
  realtime = false,
  passkeys,
}: MountOptions) {
  const onlineRef = ref(online)
  const auth = fakeAuth(signedIn ? undefined : null)
  const ctx: AppContext = createAppContext({ repo, auth, passkeys, prefs, clock: fixedClock, online: onlineRef, realtime })
  const router = createAppRouter(auth, createMemoryHistory())
  const Host = defineComponent({
    render: () => [h(RouterView), h(Toast), h(ConfirmDialog)],
  })
  const wrapper = mount(Host, {
    attachTo: document.body,
    global: {
      plugins: [{ install: installUi }, router],
      provide: { [APP_CONTEXT as symbol]: ctx },
    },
  })
  mounted.push(() => {
    wrapper.unmount()
    ctx.dispose()
  })
  await router.push(path)
  await router.isReady()
  await settle()
  return { wrapper, repo, ctx, router, auth, online: onlineRef, prefs }
}

const mounted: (() => void)[] = []

/** Unmounts everything mountApp() created (called after each test). */
export function unmountAll() {
  mounted.splice(0).forEach((stop) => stop())
}

/** Lets fetches, re-renders and lazy route components finish. */
export async function settle() {
  for (let i = 0; i < 5; i++) {
    await flushPromises()
    await new Promise((r) => setTimeout(r, 0))
  }
}

/** The grid cell input at (row, column). */
export function cell(row: number, col: number): HTMLInputElement {
  const el = document.querySelector<HTMLInputElement>(`input[data-row="${row}"][data-col="${col}"]`)
  if (!el) throw new Error(`No grid cell at row ${row}, column ${col}`)
  return el
}

export function byTestId<T extends Element = HTMLElement>(id: string): T | null {
  return document.querySelector<T>(`[data-testid="${id}"]`)
}

export function buttonByText(text: string | RegExp): HTMLButtonElement {
  const buttons = [...document.querySelectorAll<HTMLButtonElement>('button')]
  const b = buttons.find((x) => (typeof text === 'string' ? x.textContent?.trim() === text : text.test(x.textContent ?? '')))
  if (!b) throw new Error(`No button "${String(text)}". Buttons: ${buttons.map((x) => x.textContent?.trim()).join(' | ')}`)
  return b
}
