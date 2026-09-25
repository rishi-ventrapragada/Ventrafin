<script setup lang="ts">
import Button from 'primevue/button'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { computed } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import { useApp } from '@/data/appContext'
import { describeError } from '@/lib/errors'

const app = useApp()
const confirm = useConfirm()
const toast = useToast()

const live = computed(() =>
  app.live.value === 'live' ? 'Connected. Changes on the phone show here within seconds.' : 'Reconnecting to live updates…',
)

function signOut() {
  confirm.require({
    header: 'Sign out?',
    message: 'Your data stays in your account. Sign in with Google to come back. The phone stays signed in.',
    acceptLabel: 'Sign out',
    rejectLabel: 'Cancel',
    rejectProps: { severity: 'secondary', outlined: true },
    accept: async () => {
      try {
        await app.auth.signOut()
      } catch (e) {
        toast.add({ severity: 'error', summary: 'Sign-out failed', detail: describeError(e) })
      }
    },
  })
}
</script>

<template>
  <div class="flex max-w-3xl flex-col gap-3">
    <h1 class="text-xl font-semibold text-slate-800">Settings</h1>

    <section class="card divide-y divide-slate-100">
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="person" :size="26" class="text-slate-600" />
        <div class="mr-auto">
          <div class="font-medium">Signed in with Google</div>
          <div class="text-sm text-slate-600">{{ app.auth.user.value?.email }}</div>
        </div>
        <Button label="Sign out" severity="secondary" outlined @click="signOut">
          <template #icon><AppIcon name="logout" :size="20" /></template>
        </Button>
      </div>
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="sync" :size="26" class="text-slate-600" />
        <div>
          <div class="font-medium">Sync with the phone</div>
          <div class="text-sm text-slate-600">{{ app.online.value ? live : 'Offline.' }}</div>
        </div>
      </div>
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="palette" :size="26" class="text-slate-600" />
        <div>
          <div class="font-medium">Theme</div>
          <div class="text-sm text-slate-600">Ocean. More themes are coming in a later update.</div>
        </div>
      </div>
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="lock" :size="26" class="text-slate-600" />
        <div>
          <div class="font-medium">Privacy</div>
          <div class="text-sm text-slate-600">
            Your entries are stored only in your Ventrafin account. This browser keeps just your sign-in and the last
            account and payment method you used. Sign out on a shared computer. Windows Hello sign-in is planned for a
            later update.
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
