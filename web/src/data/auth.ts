import { shallowRef, type Ref } from 'vue'
import { toAppError } from '@/lib/errors'
import type { AppSupabaseClient } from './supabaseClient'

export interface AppUser {
  id: string
  email: string
  name: string | null
}

/** Sign-in state for the router guard and the pages (Google only, ARCHITECTURE.md § 5). */
export interface AuthService {
  readonly user: Readonly<Ref<AppUser | null>>
  /** Resolves once the stored session has been restored (and any ?code= exchanged). */
  readonly ready: Promise<void>
  /** Leaves the app for Google; comes back to /auth/callback. */
  signInWithGoogle(): Promise<void>
  signOut(): Promise<void>
}

/** Where to go after the Google round trip (kept in sessionStorage across the redirect). */
const NEXT_KEY = 'ventrafin.nextPath'

/** Only same-app paths, never `//evil.example` or a full URL. */
export function safeNextPath(path: unknown): string | null {
  return typeof path === 'string' && /^\/(?![/\\])/.test(path) && !path.startsWith('/login') && !path.startsWith('/auth/')
    ? path
    : null
}

export function rememberNextPath(path: unknown): void {
  const safe = safeNextPath(path)
  try {
    if (safe) sessionStorage.setItem(NEXT_KEY, safe)
    else sessionStorage.removeItem(NEXT_KEY)
  } catch {
    // Storage blocked: after sign-in the Dashboard opens instead.
  }
}

export function takeNextPath(): string | null {
  try {
    const path = sessionStorage.getItem(NEXT_KEY)
    sessionStorage.removeItem(NEXT_KEY)
    return safeNextPath(path)
  } catch {
    return null
  }
}

export function createSupabaseAuth(client: AppSupabaseClient): AuthService {
  const user = shallowRef<AppUser | null>(null)

  const setFrom = (u: { id: string; email?: string; user_metadata?: Record<string, unknown> } | null | undefined) => {
    const next: AppUser | null = u
      ? {
          id: u.id,
          email: u.email ?? '',
          name: typeof u.user_metadata?.full_name === 'string' ? u.user_metadata.full_name : null,
        }
      : null
    // Only a different user (or sign-out) changes the ref, not token refreshes.
    if (next?.id !== user.value?.id || next?.email !== user.value?.email) user.value = next
  }

  client.auth.onAuthStateChange((_event, session) => setFrom(session?.user))

  // getSession() waits for supabase-js to finish initialising, which includes
  // exchanging the ?code= from Google's redirect for a session (PKCE).
  const ready = client.auth
    .getSession()
    .then(({ data }) => setFrom(data.session?.user))
    .catch(() => setFrom(null))

  return {
    user,
    ready,
    async signInWithGoogle() {
      const { error } = await client.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${window.location.origin}/auth/callback`,
          queryParams: { prompt: 'select_account' },
        },
      })
      if (error) throw toAppError(error)
    },
    async signOut() {
      // 'local': this browser only; the phone stays signed in.
      const { error } = await client.auth.signOut({ scope: 'local' })
      if (error) throw toAppError(error)
      setFrom(null)
    },
  }
}
