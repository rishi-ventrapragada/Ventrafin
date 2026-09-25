<script setup lang="ts">
defineProps<{ problem: string }>()
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-6">
    <div class="card max-w-lg p-6">
      <h1 class="mb-2 text-lg font-semibold">Ventrafin needs its settings</h1>
      <p class="mb-3 text-slate-700">{{ problem }}</p>
      <p class="text-sm text-slate-600">
        Copy <code>web/.env.example</code> to <code>web/.env.local</code>, fill in the Supabase URL and the
        <strong>publishable</strong> key, and restart <code>npm run dev</code>. On Vercel, set the same two variables in
        the project's Environment Variables and redeploy.
      </p>
    </div>
  </div>
</template>
