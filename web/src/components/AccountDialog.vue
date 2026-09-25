<script setup lang="ts">
// Add an account, or edit one: its name and type, and archive it (PRD
// § 4.1). Accounts are archived, never deleted: their transactions and bills
// keep them. The last active account can't be archived (the database refuses
// it too). Same fields, rules and wording as the phone. Opens on the name;
// Enter saves; X or Escape asks before throwing away what was typed.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { useToast } from 'primevue/usetoast'
import { computed, ref, useId, watch } from 'vue'
import { useApp } from '@/data/appContext'
import { submitOnEnter } from '@/directives'
import { ACTIVE_ACCOUNT_NEEDED, describeError } from '@/lib/errors'
import { ACCOUNT_NAME_MAX, ACCOUNT_TYPES, ACCOUNT_TYPE_ORDER, accountNameError, type Account, type AccountType } from '@/lib/models'
import AccountAvatar from './AccountAvatar.vue'
import AppIcon from './AppIcon.vue'
import { useGuardedClose } from './useAsk'

/** `undefined`: closed; `null`: a new account; an account: edit it. */
const props = defineProps<{ account: Account | null | undefined }>()
const emit = defineEmits<{ close: [] }>()

const app = useApp()
const toast = useToast()
const formId = useId()

const name = ref('')
const type = ref<AccountType>('bank')
const tried = ref(false)
const saving = ref(false)
const error = ref<string | null>(null)
/** Generated once per opening, so retrying a failed add can't add the account twice. */
let newId = ''

watch(
  () => props.account,
  (a) => {
    if (a === undefined) return
    tried.value = false
    error.value = null
    name.value = a?.name ?? ''
    type.value = a?.type ?? 'bank'
    if (!a) newId = crypto.randomUUID()
  },
  { immediate: true },
)

const accounts = computed(() => app.accounts.data.value ?? [])
const nameError = computed(() => accountNameError(name.value, { existing: accounts.value, exceptId: props.account?.id }))
const changed = computed(() =>
  props.account ? name.value.trim() !== props.account.name || type.value !== props.account.type : name.value.trim() !== '',
)
/** Archiving this one would leave no active account. */
const lastActive = computed(() => !!props.account && !accounts.value.some((a) => a.id !== props.account!.id && !a.archived))

const { requestClose, ask, asking } = useGuardedClose(
  () => changed.value,
  () => emit('close'),
)
const visible = computed({
  get: () => props.account !== undefined,
  set: (v) => {
    if (!v && !saving.value && !asking.value) void requestClose()
  },
})

async function save() {
  tried.value = true
  if (nameError.value || saving.value) return
  const a = props.account
  if (a && !changed.value) return emit('close')
  error.value = null
  saving.value = true
  const newName = name.value.trim()
  try {
    app.requireOnline()
    if (a) await app.repo.updateAccount(a.id, newName, type.value)
    else await app.repo.insertAccount(newId, newName, type.value)
  } catch (e) {
    error.value = `Not saved. ${describeError(e)}`
    return
  } finally {
    saving.value = false
  }
  app.bump(['accounts'])
  toast.add({ severity: 'success', summary: `${a ? 'Saved' : 'Added'} ${newName}`, life: 3000 })
  emit('close')
}

async function archive() {
  const a = props.account
  if (!a || lastActive.value || saving.value) return
  const yes = await ask({
    header: `Archive ${a.name}?`,
    message: 'It disappears from the account pickers. Its transactions and bills keep it, and you can restore it any time.',
    acceptLabel: 'Archive',
    rejectLabel: 'Cancel',
    defaultFocus: 'reject',
    rejectProps: { severity: 'secondary', outlined: true },
  })
  if (!yes) return
  error.value = null
  saving.value = true
  try {
    app.requireOnline()
    await app.repo.setAccountArchived(a.id, true)
  } catch (e) {
    error.value = `Not archived. ${describeError(e)}`
    return
  } finally {
    saving.value = false
  }
  app.bump(['accounts'])
  toast.add({ severity: 'success', summary: `Archived ${a.name}`, life: 3000 })
  emit('close')
}
</script>

<template>
  <Dialog v-model:visible="visible" modal :header="account ? 'Edit account' : 'Add account'" :style="{ width: 'min(30rem, 96vw)' }">
    <form :id="formId" class="flex flex-col gap-3" data-testid="account-form" @submit.prevent="save" @keydown="submitOnEnter">
      <label class="flex flex-col gap-1">
        <span class="font-medium text-slate-700">Name</span>
        <input
          v-model="name"
          :maxlength="ACCOUNT_NAME_MAX + 10"
          class="focus-ring w-full rounded-md border px-2.5 py-1.5 focus:border-primary"
          :class="(tried || name) && nameError ? 'border-expense' : 'border-slate-300'"
          data-testid="account-name"
          autocomplete="off"
          autofocus
        />
        <span v-if="(tried || name.trim()) && nameError" class="text-sm text-expense" data-testid="account-name-error">{{ nameError }}</span>
      </label>
      <div>
        <div class="mb-1 font-medium text-slate-700">Type</div>
        <div class="flex flex-wrap gap-2" role="radiogroup" aria-label="Type">
          <label
            v-for="t in ACCOUNT_TYPE_ORDER"
            :key="t"
            class="inline-flex cursor-pointer items-center gap-2 rounded-md border px-3 py-1.5"
            :class="type === t ? 'border-primary bg-primary-soft font-semibold' : 'border-slate-300 hover:bg-slate-50'"
          >
            <input v-model="type" type="radio" name="account-type" :value="t" class="accent-[var(--vf-primary)]" :data-testid="`account-type-${t}`" />
            <AccountAvatar :type="t" :size="24" />
            {{ ACCOUNT_TYPES[t].label }}
          </label>
        </div>
      </div>
      <p v-if="account && lastActive" class="text-sm text-slate-600" data-testid="account-last-active">{{ ACTIVE_ACCOUNT_NEEDED }}</p>
      <p v-if="error" class="text-sm text-expense" role="alert">{{ error }}</p>
    </form>
    <template #footer>
      <div class="flex w-full items-center gap-2">
        <Button
          v-if="account"
          label="Archive"
          severity="secondary"
          outlined
          class="mr-auto"
          :disabled="saving || lastActive"
          data-testid="account-archive"
          @click="archive"
        >
          <template #icon><AppIcon name="archive" :size="19" /></template>
        </Button>
        <Button label="Cancel" severity="secondary" text :disabled="saving" @click="emit('close')" />
        <Button type="submit" :form="formId" :label="account ? 'Save' : 'Add account'" :loading="saving" data-testid="account-save" />
      </div>
    </template>
  </Dialog>
</template>
