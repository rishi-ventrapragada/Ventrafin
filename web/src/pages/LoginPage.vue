<script setup lang="ts">
// Google is the only way in (no passwords to manage or reset, PRD § 4.10).
import Button from 'primevue/button'
import { ref } from 'vue'
import { useRoute } from 'vue-router'
import AppLogo from '@/components/AppLogo.vue'
import { useApp } from '@/data/appContext'
import { rememberNextPath } from '@/data/auth'
import { describeError } from '@/lib/errors'

const app = useApp()
const route = useRoute()
const busy = ref(false)
const error = ref<string | null>(typeof route.query.error === 'string' ? route.query.error : null)

async function signIn() {
  error.value = null
  if (!app.online.value) {
    error.value = "There's no internet connection. Connect and try again."
    return
  }
  busy.value = true
  rememberNextPath(route.query.next)
  try {
    await app.auth.signInWithGoogle() // leaves the page for Google
  } catch (e) {
    busy.value = false
    error.value = describeError(e)
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#e3f2fd] to-[#e0f2f1] p-6">
    <div class="card w-full max-w-sm p-8 text-center shadow-sm">
      <AppLogo :size="56" class="mx-auto mb-3" />
      <h1 class="text-2xl font-semibold text-slate-800">Ventrafin</h1>
      <p class="mt-1 mb-6 text-slate-500">Home finances, on the PC and the phone.</p>
      <Button
        class="w-full"
        :loading="busy"
        label="Sign in with Google"
        data-testid="google-sign-in"
        @click="signIn"
      >
        <template #icon>
          <svg viewBox="0 0 48 48" width="18" height="18" aria-hidden="true" class="mr-1 rounded-full bg-white p-[2px]">
            <path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9 3.6l6.7-6.7C35.6 2.4 30.2 0 24 0 14.6 0 6.6 5.4 2.7 13.2l7.8 6.1C12.4 13.6 17.7 9.5 24 9.5z" />
            <path fill="#4285F4" d="M46.1 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.4c-.5 2.9-2.2 5.3-4.6 6.9l7.4 5.8c4.3-4 6.9-9.9 6.9-17.2z" />
            <path fill="#FBBC05" d="M10.5 28.7A14.5 14.5 0 0 1 9.5 24c0-1.6.3-3.2.8-4.7l-7.8-6.1A24 24 0 0 0 0 24c0 3.9.9 7.5 2.6 10.8l7.9-6.1z" />
            <path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.4-5.8c-2.1 1.4-4.8 2.3-8.5 2.3-6.3 0-11.6-4.2-13.5-9.9l-7.9 6.1C6.6 42.6 14.6 48 24 48z" />
          </svg>
        </template>
      </Button>
      <p v-if="error" class="mt-4 text-sm text-expense" role="alert">{{ error }}</p>
      <p class="mt-6 text-xs text-slate-400">Your data is private to your Google account.</p>
    </div>
  </div>
</template>
