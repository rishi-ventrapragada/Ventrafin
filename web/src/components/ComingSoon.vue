<script setup lang="ts">
// Placeholder for sections built in later phases (PRD § 7). The route
// exists now so navigation is complete.
import AppIcon from './AppIcon.vue'

defineProps<{ title: string; icon: string; note: string }>()
</script>

<template>
  <div class="flex flex-col gap-3">
    <h1 class="text-xl font-semibold text-slate-800">{{ title }}</h1>
    <div class="card flex items-center gap-4 p-6 text-slate-600">
      <AppIcon :name="icon" :size="52" class="text-slate-400" />
      <p>{{ note }}</p>
    </div>
  </div>
</template>
