<script setup lang="ts">
// Same as the phone for now: the accounts with their type. (Adding and
// renaming accounts come in a later phase, on both apps.)
import Button from 'primevue/button'
import { computed } from 'vue'
import AccountAvatar from '@/components/AccountAvatar.vue'
import { useApp } from '@/data/appContext'
import { describeError } from '@/lib/errors'
import { ACCOUNT_TYPES } from '@/lib/models'

const app = useApp()
const accounts = computed(() => app.accounts.data.value)
</script>

<template>
  <div class="flex max-w-3xl flex-col gap-3">
    <h1 class="text-xl font-semibold text-slate-800">Accounts</h1>
    <div v-if="!accounts && app.accounts.error.value" class="card flex items-center gap-3 p-4" role="alert">
      <span>Couldn't load accounts. {{ describeError(app.accounts.error.value) }}</span>
      <Button label="Retry" size="small" @click="app.accounts.refresh()" />
    </div>
    <div v-else-if="!accounts" class="muted">Loading…</div>
    <div v-else class="card overflow-hidden">
      <table class="dense-table" data-testid="accounts-table">
        <thead>
          <tr>
            <th class="w-10"></th>
            <th>Account</th>
            <th>Type</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="a in accounts" :key="a.id">
            <td><AccountAvatar :type="a.type" :size="28" /></td>
            <td class="font-medium">{{ a.name }}</td>
            <td class="text-slate-600">{{ ACCOUNT_TYPES[a.type].label }}</td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="text-sm text-slate-500">Adding and renaming accounts is coming in a later update.</p>
  </div>
</template>
