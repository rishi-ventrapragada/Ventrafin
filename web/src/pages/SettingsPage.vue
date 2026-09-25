<script setup lang="ts">
import Button from 'primevue/button'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { computed, ref } from 'vue'
import { RouterLink } from 'vue-router'
import AppIcon from '@/components/AppIcon.vue'
import ExportDialog from '@/components/ExportDialog.vue'
import PasskeySection from '@/components/PasskeySection.vue'
import ImportDialog from '@/components/import/ImportDialog.vue'
import { useApp } from '@/data/appContext'
import { describeError } from '@/lib/errors'
import { formatTimeOfDay } from '@/lib/models'
import { THEMES, themeById, type ThemeId } from '@/lib/theme'

const app = useApp()
const confirm = useConfirm()
const toast = useToast()

const live = computed(() =>
  app.live.value === 'live' ? 'Connected. Changes on the phone show here within seconds.' : 'Reconnecting to live updates…',
)
const profile = computed(() => app.profile.data.value)
const exportVisible = ref(false)
const importVisible = ref(false)

async function pickTheme(id: ThemeId) {
  if (id === app.themeId.value) return
  try {
    await app.setTheme(id)
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Theme not saved', detail: describeError(e), life: 5000 })
  }
}

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
  <div class="flex max-w-4xl flex-col gap-3">
    <h1 class="text-xl font-semibold text-slate-800">Settings</h1>

    <section class="card p-4" data-testid="theme-picker">
      <div class="mb-3 flex items-center gap-3">
        <AppIcon name="palette" :size="26" class="text-slate-600" />
        <div>
          <h2 class="font-medium">Theme</h2>
          <div class="text-sm text-slate-600">Changes the phone too. Amounts keep their red and green in every theme.</div>
        </div>
      </div>
      <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3" role="radiogroup" aria-label="Theme">
        <button
          v-for="t in THEMES"
          :key="t.id"
          type="button"
          role="radio"
          :aria-checked="app.themeId.value === t.id"
          class="flex items-center gap-3 rounded-lg border p-2 text-left transition-colors"
          :class="app.themeId.value === t.id ? 'border-primary bg-primary-soft ring-1 ring-primary' : 'border-slate-200 hover:bg-slate-50'"
          :data-theme-option="t.id"
          :disabled="!profile"
          @click="pickTheme(t.id)"
        >
          <span class="flex h-10 w-20 shrink-0 overflow-hidden rounded-md border border-slate-200" aria-hidden="true">
            <span class="flex flex-[3] items-center justify-center text-sm font-bold" :style="{ background: t.brand, color: t.onBrand }">Aa</span>
            <span class="flex-[2]" :style="{ background: t.accent }" />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block font-medium">{{ t.name }}</span>
            <span class="block text-sm text-slate-600">{{ t.description }}</span>
          </span>
          <AppIcon
            :name="app.themeId.value === t.id ? 'radio_button_checked' : 'radio_button_unchecked'"
            :size="22"
            :class="app.themeId.value === t.id ? 'text-primary' : 'text-slate-500'"
          />
        </button>
      </div>
    </section>

    <section class="card divide-y divide-slate-100" data-testid="your-data">
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="download" :size="26" class="text-slate-600" />
        <div class="mr-auto">
          <div class="font-medium">Download transactions for Excel</div>
          <div class="text-sm text-slate-600">
            A CSV file for a month, a financial year, any dates or everything. The phone can share the same file.
          </div>
        </div>
        <Button label="Export…" severity="secondary" outlined data-testid="settings-export" @click="exportVisible = true">
          <template #icon><AppIcon name="download" :size="20" /></template>
        </Button>
      </div>
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="upload_file" :size="26" class="text-slate-600" />
        <div class="mr-auto">
          <div class="font-medium">Import transactions from a CSV file</div>
          <div class="text-sm text-slate-600">
            A bank statement or spreadsheet saved as CSV. You see every row before anything is saved, and rows already in
            Ventrafin are skipped. To copy a few rows, Paste from Excel on the Add page is quicker.
          </div>
        </div>
        <Button label="Import…" severity="secondary" outlined data-testid="settings-import" @click="importVisible = true">
          <template #icon><AppIcon name="upload_file" :size="20" /></template>
        </Button>
      </div>
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="database" :size="26" class="text-slate-600" />
        <div>
          <div class="font-medium">Backups</div>
          <div class="text-sm text-slate-600">
            Every week an encrypted copy of your entries is made automatically and kept for 90 days, separately from the
            app's server, so nothing is lost if the server has a problem. Only the app's administrator can restore it.
          </div>
        </div>
      </div>
    </section>

    <section class="card divide-y divide-slate-100">
      <div class="flex items-start gap-3 p-4" data-testid="reminders-summary">
        <AppIcon name="notifications" :size="26" class="mt-0.5 text-slate-600" />
        <div class="mr-auto">
          <div class="font-medium">Reminders (on the phone)</div>
          <ul v-if="profile" class="mt-1 text-sm text-slate-700">
            <li>
              Daily "log today's expenses":
              <strong>{{ profile.dailyReminderEnabled ? `on, at ${formatTimeOfDay(profile.dailyReminderTime)}` : 'off' }}</strong>
            </li>
            <li>
              Bills and EMIs:
              <strong>
                {{
                  !profile.billRemindersEnabled
                    ? 'off for all bills'
                    : profile.billReminderDaysBefore === 0
                      ? 'on the due date, at 9:00 am'
                      : `${profile.billReminderDaysBefore} ${profile.billReminderDaysBefore === 1 ? 'day' : 'days'} before and on the due date, at 9:00 am`
                }}
              </strong>
            </li>
          </ul>
          <div v-else class="text-sm text-slate-600">…</div>
          <div class="mt-1 text-sm text-slate-600">
            Reminders are notifications on the phone, so they are set in the phone's More › Settings. The web app shows
            what's due on the <RouterLink to="/bills" class="font-medium text-primary hover:underline">Bills</RouterLink> page.
          </div>
        </div>
      </div>
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
      <PasskeySection />
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="sync" :size="26" class="text-slate-600" />
        <div>
          <div class="font-medium">Sync with the phone</div>
          <div class="text-sm text-slate-600">{{ app.online.value ? live : 'Offline.' }}</div>
        </div>
      </div>
      <div class="flex items-center gap-3 p-4">
        <AppIcon name="lock" :size="26" class="text-slate-600" />
        <div>
          <div class="font-medium">Privacy</div>
          <div class="text-sm text-slate-600">
            Your entries are stored only in your Ventrafin account (plus the weekly encrypted backup above). This browser
            keeps just your sign-in, the theme, the last account and payment method you used, and whether Windows Hello
            is set up. Windows Hello itself stays in Windows; Ventrafin never sees your face, fingerprint or PIN. Sign out
            on a shared computer.
          </div>
        </div>
      </div>
    </section>
    <p class="sr-only">Current theme: {{ themeById(app.themeId.value).name }}</p>

    <ExportDialog v-if="exportVisible" v-model:visible="exportVisible" />
    <ImportDialog v-if="importVisible" v-model:visible="importVisible" />
  </div>
</template>
