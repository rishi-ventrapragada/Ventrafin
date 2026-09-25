<script setup lang="ts">
// A red strip across the top while the browser is offline. Ventrafin has no
// offline mode (PRD § 5), so this says plainly that nothing can be saved or
// loaded until the connection is back. Same wording as the phone.
import { useApp } from '@/data/appContext'
import AppIcon from './AppIcon.vue'

const app = useApp()
</script>

<template>
  <div
    v-if="!app.online.value"
    role="alert"
    data-testid="offline-banner"
    class="flex items-center gap-2 bg-[#b3261e] px-4 py-1.5 text-sm text-white"
  >
    <AppIcon name="wifi_off" :size="18" />
    No internet connection. Entries can't be saved or loaded until you're back online.
  </div>
</template>
