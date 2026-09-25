<script setup lang="ts">
import { ACCOUNT_TYPES, type AccountType } from '@/lib/models'
import IconCircle from './IconCircle.vue'

withDefaults(defineProps<{ type: AccountType; size?: number }>(), { size: 28 })
</script>

<template>
  <IconCircle :icon="ACCOUNT_TYPES[type].icon.name" :color="ACCOUNT_TYPES[type].color" :size="size" :label="ACCOUNT_TYPES[type].label" />
</template>
