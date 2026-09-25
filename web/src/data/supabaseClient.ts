import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/database.types'

/**
 * How long any single request may take before it counts as "couldn't reach
 * the server". Without a limit a dead connection could leave a save
 * spinning forever, which would amount to failing silently.
 */
export const REQUEST_TIMEOUT_MS = 15_000

export interface AppConfig {
  supabaseUrl: string
  supabaseKey: string
}

/** Reads the build-time config; returns why it's unusable instead of throwing. */
export function readConfig(env: ImportMetaEnv = import.meta.env): AppConfig | { problem: string } {
  const url = env.VITE_SUPABASE_URL?.trim() ?? ''
  const key = env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ?? ''
  if (!url || !key) return { problem: 'VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY are not set.' }
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)) {
    return { problem: `VITE_SUPABASE_URL must look like https://<project-ref>.supabase.co (got "${url}").` }
  }
  if (/^sb_secret_/.test(key) || /service_role/.test(atobSafe(key.split('.')[1] ?? ''))) {
    return { problem: 'VITE_SUPABASE_PUBLISHABLE_KEY is a SECRET key. Use the publishable key; never ship a secret key.' }
  }
  return { supabaseUrl: url, supabaseKey: key }
}

function atobSafe(s: string): string {
  try {
    return atob(s.replace(/-/g, '+').replace(/_/g, '/'))
  } catch {
    return ''
  }
}

function fetchWithTimeout(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS)
  const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout
  return fetch(input, { ...init, signal })
}

export type AppSupabaseClient = SupabaseClient<Database>

export function createSupabase(config: AppConfig): AppSupabaseClient {
  return createClient<Database>(config.supabaseUrl, config.supabaseKey, {
    auth: {
      // Browser OAuth with PKCE: Google -> Supabase -> /auth/callback?code=…
      flowType: 'pkce',
      detectSessionInUrl: true,
      persistSession: true,
      autoRefreshToken: true,
    },
    global: { fetch: fetchWithTimeout },
  })
}
