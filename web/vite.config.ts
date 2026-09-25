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
  },
})
