<script setup lang="ts">
// Sidebar with one route per section (DECISIONS.md D8), a slim top bar with
// the page title and the live-sync status, and the offline banner. Below
// SIDEBAR_RAIL_BELOW pixels wide the sidebar is a rail of icons (names as
// tooltips), so the pages keep their width on a 1080p screen at 150 %.
import { computed } from 'vue'
import { RouterLink, RouterView, useRoute } from 'vue-router'
import { useApp } from '@/data/appContext'
import { NAV, RAIL_QUERY } from '@/lib/layout'
import AppIcon from './AppIcon.vue'
import AppLogo from './AppLogo.vue'
import OfflineBanner from './OfflineBanner.vue'
import { useMediaQuery } from './useMediaQuery'
import { useSignOut } from './useSignOut'

const app = useApp()
const route = useRoute()
const signOut = useSignOut()
const rail = useMediaQuery(RAIL_QUERY)

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
</script>

<template>
  <div class="flex h-screen min-h-0 overflow-hidden">
    <nav
      class="flex shrink-0 flex-col bg-brand text-on-brand"
      :class="rail ? 'w-14' : 'w-52'"
      aria-label="Sections"
      :data-rail="rail ? 'true' : undefined"
      data-testid="sidebar"
    >
      <div class="flex items-center gap-2 pt-4 pb-5" :class="rail ? 'justify-center' : 'px-4'">
        <AppLogo :size="32" class="rounded-md ring-1 ring-on-brand/30" />
        <span v-if="!rail" class="text-xl font-semibold tracking-wide">Ventrafin</span>
      </div>
      <ul class="flex flex-col gap-0.5" :class="rail ? 'px-1.5' : 'px-2'">
        <li v-for="item in NAV" :key="item.to">
          <RouterLink
            v-slot="{ isActive, href, navigate }"
            :to="item.to"
            custom
          >
            <!-- The current section: a darker row (text stays 4.5:1 on it in every theme), bold, a filled icon and the marker. -->
            <a
              v-tooltip.right="rail ? item.label : null"
              :href="href"
              class="flex items-center gap-3 rounded-md py-2 text-[1.03rem] transition-colors"
              :class="[
                rail ? 'justify-center px-0' : 'px-3',
                isActive ? 'bg-black/15 font-semibold shadow-[inset_3px_0_0_var(--vf-brand-indicator)]' : 'hover:bg-black/10',
              ]"
              :aria-current="isActive ? 'page' : undefined"
              :aria-label="rail ? item.label : undefined"
              @click="navigate"
            >
              <AppIcon :name="item.icon" :filled="isActive" :size="24" />
              <template v-if="!rail">{{ item.label }}</template>
            </a>
          </RouterLink>
        </li>
      </ul>
      <div class="mt-auto border-t border-on-brand/15 py-3 text-sm" :class="rail ? 'flex justify-center' : 'px-4'">
        <div v-if="!rail" class="truncate" :title="app.auth.user.value?.email">{{ app.auth.user.value?.email }}</div>
        <button
          v-tooltip.right="rail ? `Sign out (${app.auth.user.value?.email ?? ''})` : null"
          type="button"
          class="inline-flex items-center gap-1.5 rounded-md hover:underline"
          :class="rail ? 'p-2 hover:bg-black/10' : 'mt-1'"
          :aria-label="rail ? 'Sign out' : undefined"
          data-testid="sidebar-sign-out"
          @click="signOut"
        >
          <AppIcon name="logout" :size="19" /><template v-if="!rail"> Sign out</template>
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
