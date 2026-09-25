/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** https://<project-ref>.supabase.co */
  readonly VITE_SUPABASE_URL?: string
  /** The publishable key (sb_publishable_…). Never a secret / service_role key. */
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
