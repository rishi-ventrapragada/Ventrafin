<script setup lang="ts">
// Settings › Windows Hello: set up a passkey on this PC so the sign-in page
// can use face, fingerprint or PIN instead of the Google round trip. Google
// keeps working either way. Hidden behind a clear explanation when the
// browser can't do it or the server has it switched off (DECISIONS.md D26).
import Button from 'primevue/button'
import { useConfirm } from 'primevue/useconfirm'
import { computed, onMounted, ref } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import { useNotify } from '@/components/useNotify'
import { useApp } from '@/data/appContext'
import { classifyPasskeyError, describePasskeyError, type PasskeyInfo, type PasskeySupport } from '@/data/passkeys'
import { formatDateIndian, indiaToday } from '@/lib/dates'

const app = useApp()
const notify = useNotify()
const confirm = useConfirm()

const support = ref<PasskeySupport | null>(null)
const serverOn = ref<boolean | null>(null)
const passkeys = ref<PasskeyInfo[] | null>(null)
const listError = ref<string | null>(null)
const busy = ref(false)

const available = computed(() => support.value !== null && support.value !== 'none' && serverOn.value === true)

async function load() {
  listError.value = null
  try {
    passkeys.value = await app.passkeys.list()
  } catch (e) {
    listError.value = describePasskeyError(e, 'register')
  }
}

onMounted(async () => {
  const [s, on] = await Promise.all([app.passkeys.deviceSupport(), app.passkeys.serverEnabled()])
  support.value = s
  serverOn.value = on
  if (s !== 'none' && on) await load()
})

async function register() {
  if (!app.online.value) {
    notify.warn('Offline', { detail: "There's no internet connection." })
    return
  }
  busy.value = true
  try {
    await app.passkeys.register()
    notify.success('Windows Hello sign-in is set up', {
      detail: 'Next time, choose "Sign in with Windows Hello" on the sign-in page.',
      life: 6000,
    })
    await load()
  } catch (e) {
    if (classifyPasskeyError(e) === 'cancelled') notify.info('Not set up', { detail: describePasskeyError(e, 'register') })
    else notify.error("Couldn't set up Windows Hello sign-in", describePasskeyError(e, 'register'))
  } finally {
    busy.value = false
  }
}

function remove(p: PasskeyInfo) {
  confirm.require({
    header: 'Remove Windows Hello sign-in?',
    message: `"${p.name}" will no longer sign you in. Google sign-in is not affected. You can set it up again at any time.`,
    acceptLabel: 'Remove',
    rejectLabel: 'Cancel',
    defaultFocus: 'reject',
    acceptProps: { severity: 'danger' },
    rejectProps: { severity: 'secondary', outlined: true },
    accept: async () => {
      try {
        await app.passkeys.remove(p.id)
        await load()
      } catch (e) {
        notify.error('Not removed', describePasskeyError(e, 'register'))
      }
    },
  })
}

function when(ts: string): string {
  return formatDateIndian(indiaToday(() => new Date(ts)))
}
</script>

<template>
  <div class="flex items-start gap-3 p-4" data-testid="passkey-section">
    <AppIcon name="passkey" :size="26" class="mt-0.5 text-slate-600" />
    <div class="min-w-0 flex-1">
      <div class="font-medium">Sign in with Windows Hello</div>
      <div class="text-sm text-slate-600">
        Sign in on this PC with your face, fingerprint or PIN instead of going through Google each time. Google sign-in
        keeps working, and the phone is not affected.
      </div>

      <div v-if="support === null || serverOn === null" class="mt-2 text-sm text-slate-600">Checking this PC…</div>
      <div v-else-if="support === 'none'" class="mt-2 text-sm text-slate-700" data-testid="passkey-unsupported">
        <AppIcon name="info" :size="18" class="align-[-4px] text-slate-500" /> This browser can't use Windows Hello
        sign-in. Use Microsoft Edge or Google Chrome on Windows 10 or 11.
      </div>
      <div v-else-if="!serverOn" class="mt-2 text-sm text-slate-700" data-testid="passkey-server-off">
        <AppIcon name="info" :size="18" class="align-[-4px] text-slate-500" /> Not available yet: it hasn't been switched
        on for Ventrafin. Keep using Google.
      </div>
      <template v-else>
        <div v-if="support === 'roaming'" class="mt-2 text-sm text-slate-700">
          Windows Hello isn't set up on this PC (Windows Settings › Accounts › Sign-in options). Windows Hello sign-in can
          still use a phone or a security key.
        </div>
        <p v-if="listError" class="mt-2 text-sm text-expense" role="alert">{{ listError }}</p>
        <table v-if="passkeys && passkeys.length" class="dense-table mt-2 max-w-xl" data-testid="passkey-list">
          <thead>
            <tr>
              <th>Windows Hello sign-in</th>
              <th>Set up</th>
              <th>Last used</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in passkeys" :key="p.id">
              <td>{{ p.name }}</td>
              <td class="whitespace-nowrap">{{ when(p.createdAt) }}</td>
              <td class="whitespace-nowrap">{{ p.lastUsedAt ? when(p.lastUsedAt) : 'Not yet' }}</td>
              <td class="text-right">
                <Button label="Remove" severity="danger" text size="small" @click="remove(p)" />
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else-if="passkeys" class="mt-2 text-sm text-slate-600" data-testid="passkey-none">Not set up yet.</p>
      </template>
    </div>
    <Button
      v-if="available"
      label="Set up Windows Hello sign-in"
      :loading="busy"
      severity="secondary"
      outlined
      data-testid="passkey-register"
      @click="register"
    >
      <template #icon><AppIcon name="fingerprint" :size="20" /></template>
    </Button>
  </div>
</template>
