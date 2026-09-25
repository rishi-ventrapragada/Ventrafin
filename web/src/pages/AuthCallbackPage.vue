<script setup lang="ts">
// Google -> Supabase -> here with ?code=… (PKCE). supabase-js exchanges the
// code while it starts up; this page waits for that, then opens the page the
// user was heading for.
import { onMounted, ref } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { useApp } from '@/data/appContext'
import { takeNextPath } from '@/data/auth'

const app = useApp()
const route = useRoute()
const router = useRouter()
const problem = ref<string | null>(null)

onMounted(async () => {
  const oauthError = route.query.error_description ?? route.query.error
  if (typeof oauthError === 'string') {
    problem.value = oauthError.replace(/\+/g, ' ')
    return
  }
  await app.auth.ready
  if (app.auth.user.value) await router.replace(takeNextPath() ?? '/dashboard')
  else problem.value = "Google sign-in didn't finish. Please try again."
})
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-6">
    <div v-if="problem" class="card max-w-md p-6 text-center">
      <h1 class="mb-2 text-lg font-semibold">Couldn't sign in</h1>
      <p class="mb-4 text-slate-600">{{ problem }}</p>
      <RouterLink to="/login" class="font-medium text-primary hover:underline">Back to sign in</RouterLink>
    </div>
    <p v-else class="text-slate-600">Signing you in…</p>
  </div>
</template>
