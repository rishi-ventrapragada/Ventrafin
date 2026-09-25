<script setup lang="ts">
// The accounts with their type (PRD § 4.1): add one, click one to rename
// it, change its type or archive it; archived ones wait at the bottom with a
// Restore button. Accounts are archived, never deleted, because their
// transactions and bills keep them. Same as the phone.
import Button from 'primevue/button'
import { useToast } from 'primevue/usetoast'
import { computed, ref } from 'vue'
import AccountAvatar from '@/components/AccountAvatar.vue'
import AccountDialog from '@/components/AccountDialog.vue'
import AppIcon from '@/components/AppIcon.vue'
import LoadError from '@/components/LoadError.vue'
import { useApp } from '@/data/appContext'
import { describeError } from '@/lib/errors'
import { ACCOUNT_TYPES, sortByName, type Account } from '@/lib/models'

const app = useApp()
const toast = useToast()

const accounts = computed(() => app.accounts.data.value)
const active = computed(() => (accounts.value ?? []).filter((a) => !a.archived))
const archived = computed(() => sortByName((accounts.value ?? []).filter((a) => a.archived)))

/** `undefined`: closed; `null`: adding; an account: editing it. */
const editing = ref<Account | null | undefined>(undefined)
const restoring = ref<string | null>(null)

/** No confirm: restoring hides nothing and can be archived again. */
async function restore(a: Account) {
  restoring.value = a.id
  try {
    app.requireOnline()
    await app.repo.setAccountArchived(a.id, false)
    app.bump(['accounts'])
    toast.add({ severity: 'success', summary: `Restored ${a.name}`, life: 3000 })
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Not restored', detail: describeError(e), life: 5000 })
  } finally {
    restoring.value = null
  }
}
</script>

<template>
  <div class="flex max-w-3xl flex-col gap-3">
    <div class="flex items-end gap-2">
      <div class="mr-auto">
        <h1 class="text-xl font-semibold text-slate-800">Accounts</h1>
        <p class="text-sm text-slate-600">Click an account to rename it, change its type, or archive it.</p>
      </div>
      <Button label="Add account" data-testid="add-account" @click="editing = null">
        <template #icon><AppIcon name="add" :size="20" /></template>
      </Button>
    </div>

    <LoadError
      v-if="!accounts && app.accounts.error.value"
      :error="app.accounts.error.value"
      what="Couldn't load accounts."
      @retry="app.accounts.refresh()"
    />
    <div v-else-if="!accounts" class="muted">Loading…</div>
    <template v-else>
      <div class="card overflow-hidden">
        <table class="dense-table" data-testid="accounts-table">
          <thead>
            <tr>
              <th class="w-10"></th>
              <th>Account</th>
              <th>Type</th>
              <th class="w-24"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="a in active" :key="a.id" class="cursor-pointer" :data-account-id="a.id" @click="editing = a">
              <td><AccountAvatar :type="a.type" :size="32" /></td>
              <td class="font-medium">{{ a.name }}</td>
              <td class="text-slate-600">{{ ACCOUNT_TYPES[a.type].label }}</td>
              <td class="text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-medium text-primary hover:bg-primary-soft"
                  :aria-label="`Edit ${a.name}`"
                  :data-testid="`edit-account-${a.id}`"
                  @click.stop="editing = a"
                >
                  <AppIcon name="edit" :size="19" /> Edit
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="archived.length" class="card overflow-hidden">
        <table class="dense-table" data-testid="accounts-archived">
          <thead>
            <tr>
              <th class="w-10"></th>
              <th>Archived ({{ archived.length }})</th>
              <th>Type</th>
              <th class="w-28"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="a in archived" :key="a.id" :data-account-id="a.id">
              <td><AccountAvatar :type="a.type" :size="32" /></td>
              <td class="font-medium text-slate-700">{{ a.name }}</td>
              <td class="text-slate-600">{{ ACCOUNT_TYPES[a.type].label }}</td>
              <td class="text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-medium text-primary hover:bg-primary-soft disabled:opacity-60"
                  :aria-label="`Restore ${a.name}`"
                  :disabled="restoring === a.id"
                  :data-testid="`restore-${a.id}`"
                  @click="restore(a)"
                >
                  <AppIcon name="unarchive" :size="19" /> Restore
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="text-sm text-slate-600">
        Archived accounts are left out of the account pickers. Their transactions and bills keep them.
      </p>
    </template>

    <AccountDialog :account="editing" @close="editing = undefined" />
  </div>
</template>
