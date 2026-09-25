<script setup lang="ts">
// "Couldn't load …" with the plain-language reason and a Retry button, for
// every page or section that loads data (the web twin of the phone's LoadError).
import Button from 'primevue/button'
import { describeError } from '@/lib/errors'
import AppIcon from './AppIcon.vue'

withDefaults(
  defineProps<{
    error: unknown
    /** Said first, e.g. "Couldn't load the categories." */
    what?: string
    /** Inside a card section: no card of its own. */
    compact?: boolean
  }>(),
  { what: undefined, compact: false },
)
const emit = defineEmits<{ retry: [] }>()
</script>

<template>
  <div class="flex items-center gap-3" :class="compact ? 'py-2' : 'card p-4'" role="alert" data-testid="load-error">
    <AppIcon name="cloud_off" :size="compact ? 24 : 30" class="shrink-0 text-expense" />
    <span class="min-w-0">{{ what ? `${what} ${describeError(error)}` : describeError(error) }}</span>
    <Button label="Retry" size="small" class="shrink-0" data-testid="retry" @click="emit('retry')">
      <template #icon><AppIcon name="refresh" :size="18" /></template>
    </Button>
  </div>
</template>
