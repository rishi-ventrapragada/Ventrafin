// Windows Hello (a passkey) as an extra way to sign in on the web, next to
// Google, never instead of it (PRD § 4.10, DECISIONS.md D26). Uses Supabase
// Auth's passkeys (beta since May 2026; supabase-js runs the WebAuthn
// ceremony). A passkey is registered from Settings while signed in with
// Google, and then offered on the sign-in page of that browser.
//
// The option is only shown when both sides can do it:
//   * the Supabase project has passkeys switched on (its public auth
//     settings say `passkeys_enabled`), and
//   * the browser supports WebAuthn in a secure context.
import { AppError, isNetworkError } from '@/lib/errors'
import type { AppConfig, AppSupabaseClient } from './supabaseClient'

/** What this PC and browser offer. */
export type PasskeySupport =
  /** No WebAuthn (old browser, or not https): the option is hidden. */
  | 'none'
  /** Windows Hello (face, fingerprint or PIN) is set up on this PC. */
  | 'platform'
  /** WebAuthn without Windows Hello: a phone or security key can still be used. */
  | 'roaming'

export interface PasskeyInfo {
  id: string
  /** e.g. "Windows Hello", "Google Password Manager" (from the authenticator). */
  name: string
  createdAt: string
  lastUsedAt: string | null
}

export interface PasskeyService {
  /** Whether the Supabase project has passkey sign-in switched on. False when it can't be told. */
  serverEnabled(): Promise<boolean>
  deviceSupport(): Promise<PasskeySupport>
  /** Runs the Windows Hello prompt and signs in; the auth state updates like any sign-in. */
  signIn(): Promise<void>
  /** Registers a passkey for the signed-in user (Windows Hello prompt). */
  register(): Promise<PasskeyInfo>
  list(): Promise<PasskeyInfo[]>
  remove(id: string): Promise<void>
}

// ---------------------------------------------------------------------------
// "This browser's account has a passkey" (a hint for the sign-in page)
// ---------------------------------------------------------------------------

const HINT_KEY = 'ventrafin.passkeyHint'

/**
 * Remembered per browser, so the sign-in page only offers Windows Hello
 * where it was set up. Set when a passkey is registered or used here, or
 * when Settings finds the account has one; cleared when it has none.
 */
export function rememberPasskeyHint(has: boolean): void {
  try {
    if (has) localStorage.setItem(HINT_KEY, '1')
    else localStorage.removeItem(HINT_KEY)
  } catch {
    // Storage blocked: the sign-in page just shows Google.
  }
}

export function hasPasskeyHint(): boolean {
  try {
    return localStorage.getItem(HINT_KEY) === '1'
  } catch {
    return false
  }
}

// ---------------------------------------------------------------------------
// Errors in plain words
// ---------------------------------------------------------------------------

export type PasskeyProblem =
  | 'cancelled'
  | 'disabled'
  | 'already-registered'
  | 'not-registered'
  | 'expired'
  | 'too-many'
  | 'wrong-site'
  | 'unsupported'
  | 'network'
  | 'other'

/** What went wrong with a passkey step, from supabase-js / browser errors. */
export function classifyPasskeyError(e: unknown): PasskeyProblem {
  if (isNetworkError(e)) return 'network'
  const err = e as { name?: string; code?: string; message?: string } | null
  const name = err?.name ?? ''
  const code = err?.code ?? ''
  // The user closed the Windows Hello prompt, or it timed out.
  if (name === 'NotAllowedError' || name === 'AbortError' || code === 'ERROR_CEREMONY_ABORTED') return 'cancelled'
  if (code === 'passkey_disabled') return 'disabled'
  if (code === 'ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED' || code === 'webauthn_credential_exists' || name === 'InvalidStateError')
    return 'already-registered'
  if (code === 'webauthn_credential_not_found') return 'not-registered'
  if (code === 'webauthn_challenge_expired' || code === 'webauthn_challenge_not_found') return 'expired'
  if (code === 'too_many_passkeys') return 'too-many'
  if (code === 'ERROR_INVALID_DOMAIN' || code === 'ERROR_INVALID_RP_ID' || name === 'SecurityError') return 'wrong-site'
  if (name === 'NotSupportedError' || /does not support webauthn/i.test(err?.message ?? '')) return 'unsupported'
  return 'other'
}

export function describePasskeyError(e: unknown, step: 'sign-in' | 'register'): string {
  switch (classifyPasskeyError(e)) {
    case 'cancelled':
      return step === 'sign-in' ? 'Windows Hello was cancelled. Nothing changed.' : 'Setup was cancelled. Nothing was saved.'
    case 'disabled':
      return 'Windows Hello sign-in is switched off for Ventrafin at the moment. Use Google.'
    case 'already-registered':
      return 'This PC is already set up for Windows Hello sign-in.'
    case 'not-registered':
      return "This PC's Windows Hello key is no longer on your account (it was removed). Sign in with Google, then set it up again in Settings."
    case 'expired':
      return 'That took too long. Please try again.'
    case 'too-many':
      return 'Your account has the most Windows Hello sign-ins allowed. Remove one in Settings first.'
    case 'wrong-site':
      return 'Windows Hello only works on the Ventrafin site itself (ventrafin.vercel.app), not on this address.'
    case 'unsupported':
      return "This browser can't use Windows Hello. Use Google, or try Edge or Chrome."
    case 'network':
      return "Couldn't reach the server. Check your internet connection and try again."
    case 'other':
      return step === 'sign-in' ? "Windows Hello sign-in didn't work. Use Google instead." : "Couldn't set up Windows Hello. Please try again."
  }
}

// ---------------------------------------------------------------------------
// Supabase implementation
// ---------------------------------------------------------------------------

type PasskeyRow = { id: string; friendly_name?: string; created_at: string; last_used_at?: string }

function fromRow(r: PasskeyRow): PasskeyInfo {
  return { id: r.id, name: r.friendly_name?.trim() || 'Windows Hello sign-in', createdAt: r.created_at, lastUsedAt: r.last_used_at ?? null }
}

/** Re-throws supabase-js's `{ error }` so callers can classify it. */
function check<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw result.error
  if (result.data === null) throw new AppError('No response from the server')
  return result.data
}

export async function detectPasskeySupport(): Promise<PasskeySupport> {
  if (typeof window === 'undefined' || !window.isSecureContext) return 'none'
  const PKC = (window as { PublicKeyCredential?: typeof PublicKeyCredential }).PublicKeyCredential
  if (typeof PKC !== 'function' || !navigator.credentials) return 'none'
  try {
    return (await PKC.isUserVerifyingPlatformAuthenticatorAvailable()) ? 'platform' : 'roaming'
  } catch {
    return 'roaming'
  }
}

export function createSupabasePasskeys(client: AppSupabaseClient, config: AppConfig): PasskeyService {
  let enabled: Promise<boolean> | null = null
  return {
    serverEnabled() {
      // Public, needs only the publishable key; asked once per page load.
      enabled ??= fetch(`${config.supabaseUrl}/auth/v1/settings`, {
        headers: { apikey: config.supabaseKey },
        signal: AbortSignal.timeout(8000),
      })
        .then((r) => (r.ok ? r.json() : null))
        .then((s: { passkeys_enabled?: unknown } | null) => s?.passkeys_enabled === true)
        .catch(() => {
          enabled = null // ask again next time
          return false
        })
      return enabled
    },
    deviceSupport: detectPasskeySupport,
    async signIn() {
      check(await client.auth.signInWithPasskey())
      rememberPasskeyHint(true)
    },
    async register() {
      const row = check(await client.auth.registerPasskey())
      rememberPasskeyHint(true)
      return fromRow(row)
    },
    async list() {
      const rows = check(await client.auth.passkey.list())
      rememberPasskeyHint(rows.length > 0)
      return rows.map(fromRow)
    },
    async remove(id: string) {
      const { error } = await client.auth.passkey.delete({ passkeyId: id })
      if (error) throw error
    },
  }
}

/** For builds and tests without passkeys: the option never shows. */
export const noPasskeys: PasskeyService = {
  serverEnabled: async () => false,
  deviceSupport: async () => 'none',
  signIn: async () => {
    throw new AppError('Windows Hello sign-in is not available')
  },
  register: async () => {
    throw new AppError('Windows Hello sign-in is not available')
  },
  list: async () => [],
  remove: async () => {},
}
