<script setup lang="ts">
// Sidebar with one route per section (DECISIONS.md D8), a slim top bar with
// the page title and the live-sync status, and the offline banner.
import { useToast } from 'primevue/usetoast'
import { computed } from 'vue'
import { RouterLink, RouterView, useRoute } from 'vue-router'
import { useApp } from '@/data/appContext'
import { describeError } from '@/lib/errors'
import AppIcon from './AppIcon.vue'
import AppLogo from './AppLogo.vue'
import OfflineBanner from './OfflineBanner.vue'

const app = useApp()
const route = useRoute()
const toast = useToast()

const NAV = [
  { to: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
  { to: '/transactions', label: 'Transactions', icon: 'receipt_long' },
  { to: '/add', label: 'Add', icon: 'add_circle' },
  { to: '/categories', label: 'Categories', icon: 'category' },
  { to: '/accounts', label: 'Accounts', icon: 'account_balance_wallet' },
  { to: '/bills', label: 'Bills', icon: 'event_note' },
  { to: '/reports', label: 'Reports', icon: 'bar_chart' },
  { to: '/settings', label: 'Settings', icon: 'settings' },
] as const

const title = computed(() => (route.meta.title as string | undefined) ?? '')

const liveLabel = computed(() => {
  switch (app.live.value) {
    case 'live':
      return { text: 'Live', dot: 'bg-green-500', tip: 'Changes made on the phone appear here within seconds.' }
    case 'reconnecting':
      return { text: 'Reconnecting…', dot: 'bg-amber-500', tip: "Live updates paused. Changes from the phone will appear once it's back." }
    default:
      return { text: 'Connecting…', dot: 'bg-slate-400', tip: 'Connecting to live updates.' }
  }
})

async function signOut() {
  try {
    await app.auth.signOut()
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Sign-out failed', detail: describeError(e) })
  }
}
</script>

<template>
  <div class="flex h-screen min-h-0 overflow-hidden">
    <nav class="flex w-52 shrink-0 flex-col bg-ocean text-white" aria-label="Sections">
      <div class="flex items-center gap-2 px-4 pt-4 pb-5">
        <AppLogo :size="32" class="rounded-md ring-1 ring-white/30" />
        <span class="text-xl font-semibold tracking-wide">Ventrafin</span>
      </div>
      <ul class="flex flex-col gap-0.5 px-2">
        <li v-for="item in NAV" :key="item.to">
          <RouterLink
            v-slot="{ isActive, href, navigate }"
            :to="item.to"
            custom
          >
            <a
              :href="href"
              class="flex items-center gap-3 rounded-md px-3 py-2 text-[1.03rem] transition-colors"
              :class="isActive ? 'bg-white/18 font-semibold shadow-[inset_3px_0_0_#4db6ac]' : 'text-white/90 hover:bg-white/10'"
              :aria-current="isActive ? 'page' : undefined"
              @click="navigate"
            >
              <AppIcon :name="item.icon" :filled="isActive" :size="24" />
              {{ item.label }}
            </a>
          </RouterLink>
        </li>
      </ul>
      <div class="mt-auto border-t border-white/15 px-4 py-3 text-sm">
        <div class="truncate text-white/90" :title="app.auth.user.value?.email">{{ app.auth.user.value?.email }}</div>
        <button type="button" class="mt-1 inline-flex items-center gap-1.5 text-white/90 hover:text-white hover:underline" @click="signOut">
          <AppIcon name="logout" :size="19" /> Sign out
        </button>
      </div>
    </nav>

    <div class="flex min-w-0 flex-1 flex-col">
      <OfflineBanner />
      <header class="flex h-11 shrink-0 items-center gap-3 border-b border-slate-200 bg-white px-5">
        <span class="font-semibold text-slate-700">{{ title }}</span>
        <span
          v-if="app.online.value"
          v-tooltip.bottom="liveLabel.tip"
          class="ml-auto inline-flex items-center gap-1.5 text-sm text-slate-600"
          data-testid="live-status"
        >
          <span class="h-2.5 w-2.5 rounded-full" :class="liveLabel.dot" /> {{ liveLabel.text }}
        </span>
      </header>
      <main class="min-h-0 flex-1 overflow-auto px-5 py-4">
        <RouterView />
      </main>
    </div>
  </div>
</template>
