// vercel.json and the build-time config: the security settings the brief
// asks for stay in place.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { readConfig } from '@/data/supabaseClient'
import { safeNextPath } from '@/data/auth'

const vercel = JSON.parse(readFileSync(resolve(process.cwd(), 'vercel.json'), 'utf8')) as {
  rewrites: { source: string; destination: string }[]
  headers: { source: string; headers: { key: string; value: string }[] }[]
}
const mcp = JSON.parse(readFileSync(resolve(process.cwd(), '../.mcp.json'), 'utf8')) as {
  mcpServers: { supabase: { url: string } }
}
const projectRef = new URL(mcp.mcpServers.supabase.url).searchParams.get('project_ref')!

const header = (key: string) => vercel.headers.find((h) => h.source === '/(.*)')!.headers.find((h) => h.key === key)?.value ?? ''

function csp(): Record<string, string[]> {
  return Object.fromEntries(
    header('Content-Security-Policy')
      .split(';')
      .map((d) => d.trim().split(/\s+/))
      .filter((p) => p[0])
      .map(([name, ...values]) => [name!, values]),
  )
}

describe('vercel.json', () => {
  it('every path serves index.html (deep links and refreshes work)', () => {
    expect(vercel.rewrites).toEqual([{ source: '/(.*)', destination: '/index.html' }])
  })

  it('CSP allows only this origin and the project\'s Supabase URL', () => {
    const p = csp()
    expect(p['default-src']).toEqual(["'self'"])
    expect(p['script-src']).toEqual(["'self'"]) // no inline scripts, no eval
    expect(p['connect-src']).toEqual(["'self'", `https://${projectRef}.supabase.co`, `wss://${projectRef}.supabase.co`])
    expect(p['font-src']).toEqual(["'self'"]) // icons are bundled SVG; system fonts
    expect(p['img-src']).toEqual(["'self'", 'data:'])
    expect(p['frame-ancestors']).toEqual(["'none'"])
    expect(p['object-src']).toEqual(["'none'"])
  })

  it('other security headers', () => {
    expect(header('X-Frame-Options')).toBe('DENY')
    expect(header('X-Content-Type-Options')).toBe('nosniff')
    expect(header('Referrer-Policy')).toBe('strict-origin-when-cross-origin')
    expect(header('Strict-Transport-Security')).toContain('max-age=')
  })
})

describe('build-time config', () => {
  it('needs both values', () => {
    expect(readConfig({ VITE_SUPABASE_URL: '', VITE_SUPABASE_PUBLISHABLE_KEY: '' } as ImportMetaEnv)).toHaveProperty('problem')
  })

  it('accepts a project URL and a publishable key', () => {
    expect(
      readConfig({ VITE_SUPABASE_URL: 'https://abc123.supabase.co', VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_x' } as ImportMetaEnv),
    ).toEqual({ supabaseUrl: 'https://abc123.supabase.co', supabaseKey: 'sb_publishable_x' })
  })

  it('refuses a secret key, so one can never ship to the browser', () => {
    const r = readConfig({ VITE_SUPABASE_URL: 'https://abc123.supabase.co', VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_secret_x' } as ImportMetaEnv)
    expect(r).toHaveProperty('problem')
    const legacy = `x.${btoa('{"role":"service_role"}')}.y`
    expect(readConfig({ VITE_SUPABASE_URL: 'https://abc123.supabase.co', VITE_SUPABASE_PUBLISHABLE_KEY: legacy } as ImportMetaEnv)).toHaveProperty(
      'problem',
    )
  })
})

describe('return path after sign-in', () => {
  it('only same-app paths', () => {
    expect(safeNextPath('/transactions?month=2026-09')).toBe('/transactions?month=2026-09')
    expect(safeNextPath('//evil.example')).toBeNull()
    expect(safeNextPath('/\\evil.example')).toBeNull()
    expect(safeNextPath('https://evil.example')).toBeNull()
    expect(safeNextPath('/login')).toBeNull()
    expect(safeNextPath(['/add'])).toBeNull()
  })
})
