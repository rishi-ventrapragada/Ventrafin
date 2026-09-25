// The app's shared state: who is signed in, the repository, the clock,
// whether the browser is online, the Realtime connection, and a revision
// counter per table. Pages read data through liveQuery(), which re-fetches
// whenever Realtime reports a change to one of its tables, so every page
// updates when something changes on the phone, with no refresh button.
// (Same design as the phone's Riverpod "revisions", DECISIONS.md D11.)
import {
  computed,
  effectScope,
  inject,
  reactive,
  readonly,
  ref,
  shallowRef,
  watch,
  type InjectionKey,
  type Ref,
  type ShallowRef,
} from 'vue'
import { indiaToday, systemClock, type Clock } from '@/lib/dates'
import { OfflineError } from '@/lib/errors'
import type { Account, Category, Profile } from '@/lib/models'
import { applyTheme, rememberedThemeId, themeById, type ThemeId } from '@/lib/theme'
import type { AuthService } from './auth'
import type { EntryPrefs } from './entryPrefs'
import { noPasskeys, type PasskeyService } from './passkeys'
import { REALTIME_TABLES, type FinanceRepository, type LiveStatus, type RealtimeTable } from './repository'

/** Coalesces bursts (a paste of 50 rows on the phone or here) into one re-fetch. */
export const REALTIME_DEBOUNCE_MS = 300

/** After this long in a background tab, coming back re-fetches everything. */
const STALE_AFTER_HIDDEN_MS = 30_000

export interface LiveQuery<T> {
  /** The latest data; kept while a re-fetch runs or fails, so the screen doesn't flicker. */
  readonly data: ShallowRef<T | undefined>
  readonly error: ShallowRef<unknown>
  readonly loading: Ref<boolean>
  refresh(): Promise<void>
}

export interface AppContext {
  readonly repo: FinanceRepository
  readonly auth: AuthService
  /** Windows Hello sign-in (an extra option next to Google). */
  readonly passkeys: PasskeyService
  readonly clock: Clock
  readonly prefs: EntryPrefs
  /** Today in India (`yyyy-mm-dd`); ticks over at midnight IST. */
  readonly today: Readonly<Ref<string>>
  /** False when the browser knows it is offline. */
  readonly online: Readonly<Ref<boolean>>
  readonly live: Readonly<Ref<LiveStatus>>
  readonly revisions: Readonly<Record<RealtimeTable, number>>
  /** Re-fetch everything showing these tables (after a save here, or a Realtime event). */
  bump(tables: readonly RealtimeTable[]): void
  bumpAll(): void
  /** Throws OfflineError when offline, so saves are refused with a clear message. */
  requireOnline(): void
  readonly accounts: LiveQuery<Account[]>
  readonly categories: LiveQuery<Category[]>
  /** Theme and reminder settings, shared with the phone. */
  readonly profile: LiveQuery<Profile>
  /** The theme on screen: a change still saving, else the profile's, else this browser's last one. */
  readonly themeId: Readonly<Ref<ThemeId>>
  /** Applies `id` straight away and saves it to the profile; rolls back and throws if the save fails. */
  setTheme(id: ThemeId): Promise<void>
  liveQuery<T>(tables: readonly RealtimeTable[], fetcher: () => Promise<T>, deps?: () => unknown): LiveQuery<T>
  dispose(): void
}

export const APP_CONTEXT: InjectionKey<AppContext> = Symbol('ventrafin-app')

export function useApp(): AppContext {
  const ctx = inject(APP_CONTEXT)
  if (!ctx) throw new Error('useApp() called outside the app')
  return ctx
}

export interface AppContextOptions {
  repo: FinanceRepository
  auth: AuthService
  prefs: EntryPrefs
  /** Omitted: no passkey option anywhere. */
  passkeys?: PasskeyService
  clock?: Clock
  /** Tests pass a ref; the app follows navigator.onLine. */
  online?: Ref<boolean>
  /** Tests turn off the Realtime subscription and window listeners. */
  realtime?: boolean
}

export function createAppContext(opts: AppContextOptions): AppContext {
  const { repo, auth, prefs } = opts
  const clock = opts.clock ?? systemClock
  const scope = effectScope(true)
  const cleanups: (() => void)[] = []

  const today = ref(indiaToday(clock))
  const online = opts.online ?? ref(typeof navigator === 'undefined' ? true : navigator.onLine)
  const live = ref<LiveStatus>('connecting')
  const revisions = reactive(Object.fromEntries(REALTIME_TABLES.map((t) => [t, 0])) as Record<RealtimeTable, number>)

  const bump = (tables: readonly RealtimeTable[]) => {
    for (const t of tables) revisions[t]++
  }
  const bumpAll = () => bump(REALTIME_TABLES)

  function liveQuery<T>(tables: readonly RealtimeTable[], fetcher: () => Promise<T>, deps?: () => unknown): LiveQuery<T> {
    const data = shallowRef<T>()
    const error = shallowRef<unknown>(null)
    const loading = ref(false)
    let seq = 0

    async function load() {
      if (!auth.user.value) {
        data.value = undefined
        return
      }
      const mine = ++seq
      loading.value = true
      try {
        const value = await fetcher()
        if (mine === seq) {
          data.value = value
          error.value = null
        }
      } catch (e) {
        if (mine === seq) error.value = e
      } finally {
        if (mine === seq) loading.value = false
      }
    }

    // A key per input: revisions of the query's tables, its own inputs
    // (e.g. the month) and the signed-in user. Any change re-fetches.
    watch(
      () => JSON.stringify([tables.map((t) => revisions[t]), deps?.() ?? null, auth.user.value?.id ?? null]),
      () => void load(),
      { immediate: true },
    )
    return { data, error, loading, refresh: load }
  }

  const shared = scope.run(() => ({
    accounts: liveQuery(['accounts'], () => repo.fetchAccounts()),
    categories: liveQuery(['categories'], () => repo.fetchCategories()),
    profile: liveQuery(['profiles'], () => repo.fetchProfile(auth.user.value!.id)),
  }))!

  // Theme (DECISIONS.md D22): shown at once when picked here, and followed
  // when it changes on the phone (the profile re-fetches via Realtime).
  const pendingTheme = ref<ThemeId | null>(null)
  const themeId = computed<ThemeId>(
    () => pendingTheme.value ?? themeById(shared.profile.data.value?.theme ?? rememberedThemeId()).id,
  )
  scope.run(() => watch(themeId, (id) => applyTheme(themeById(id))))
  let themeSeq = 0
  async function setTheme(id: ThemeId) {
    const user = auth.user.value
    if (!user) return
    if (!online.value) throw new OfflineError()
    const mine = ++themeSeq
    pendingTheme.value = id
    try {
      await repo.updateProfileTheme(user.id, id)
      bump(['profiles'])
      await shared.profile.refresh()
    } finally {
      if (mine === themeSeq) pendingTheme.value = null
    }
  }

  if (opts.realtime !== false) {
    scope.run(() => {
      // Realtime while signed in, debounced into revision bumps.
      let unsubscribe: (() => void) | null = null
      let timer: ReturnType<typeof setTimeout> | undefined
      const pending = new Set<RealtimeTable>()
      watch(
        () => auth.user.value?.id,
        (userId) => {
          unsubscribe?.()
          unsubscribe = null
          pending.clear()
          if (!userId) return
          let active = true
          const stop = repo.watchChanges(
            userId,
            (change) => {
              if (!active) return
              if ('resync' in change) return bumpAll()
              pending.add(change.table)
              clearTimeout(timer)
              timer = setTimeout(() => {
                bump([...pending])
                pending.clear()
              }, REALTIME_DEBOUNCE_MS)
            },
            (status) => {
              if (active) live.value = status
            },
          )
          unsubscribe = () => {
            active = false
            clearTimeout(timer)
            stop()
          }
        },
        { immediate: true },
      )
      cleanups.push(() => unsubscribe?.())
    })

    if (typeof window !== 'undefined') {
      const setOnline = () => {
        const was = online.value
        online.value = navigator.onLine
        // Back online: re-fetch whatever changed while the connection was down.
        if (!was && online.value) bumpAll()
      }
      let hiddenAt = 0
      const onVisibility = () => {
        if (document.visibilityState === 'hidden') hiddenAt = Date.now()
        else {
          today.value = indiaToday(clock)
          if (hiddenAt && Date.now() - hiddenAt > STALE_AFTER_HIDDEN_MS) bumpAll()
        }
      }
      window.addEventListener('online', setOnline)
      window.addEventListener('offline', setOnline)
      document.addEventListener('visibilitychange', onVisibility)
      const tick = setInterval(() => (today.value = indiaToday(clock)), 60_000)
      cleanups.push(() => {
        window.removeEventListener('online', setOnline)
        window.removeEventListener('offline', setOnline)
        document.removeEventListener('visibilitychange', onVisibility)
        clearInterval(tick)
      })
    }
  }

  return {
    repo,
    auth,
    passkeys: opts.passkeys ?? noPasskeys,
    clock,
    prefs,
    today: readonly(today),
    online: readonly(online),
    live: readonly(live),
    revisions: readonly(revisions) as Readonly<Record<RealtimeTable, number>>,
    bump,
    bumpAll,
    requireOnline() {
      if (!online.value) throw new OfflineError()
    },
    accounts: shared.accounts,
    categories: shared.categories,
    profile: shared.profile,
    themeId,
    setTheme,
    // Called from a page's setup(), so its watcher stops when the page unmounts.
    liveQuery,
    dispose() {
      cleanups.forEach((c) => c())
      scope.stop()
    },
  }
}
