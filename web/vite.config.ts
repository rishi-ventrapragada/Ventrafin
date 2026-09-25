/// <reference types="vitest/config" />
import { fileURLToPath } from 'node:url'
import tailwindcss from '@tailwindcss/vite'
import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'

const repoRoot = fileURLToPath(new URL('..', import.meta.url))

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: {
    // http://localhost:5173 is the URL allow-listed for Google sign-in redirects.
    port: 5173,
    strictPort: true,
    // /shared/category-style.json lives outside this folder.
    fs: { allow: [repoRoot] },
  },
  preview: { port: 5173, strictPort: true },
  build: {
    target: 'es2022',
    sourcemap: false,
    // PrimeVue + its theme + supabase-js make a ~160 kB (gzip) main chunk; fine for a desktop app.
    chunkSizeWarningLimit: 800,
  },
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.test.ts'],
    setupFiles: ['tests/setup.ts'],
    restoreMocks: true,
    // Component tests mount the whole app (router, PrimeVue, dialogs); with
    // every file running in parallel one can take longer than vitest's 5 s
    // default on a busy PC, so a normal run was flaky. 20 s still catches a hang.
    testTimeout: 20_000,
  },
})
