<script setup lang="ts">
// This month against last: spending more is red and up, less is green and
// down (the phone's _Change). For income, up is the good direction.
import { computed } from 'vue'
import { formatRupeesCompact } from '@/lib/money'
import AppIcon from './AppIcon.vue'

const props = withDefaults(defineProps<{ now: number; before: number; upIsGood?: boolean }>(), { upIsGood: false })

const view = computed(() => {
  const diff = props.now - props.before
  if (diff === 0) return { text: 'same', color: 'text-slate-400', icon: null }
  if (props.before === 0) return { text: 'new', color: props.upIsGood ? 'text-income' : 'text-expense', icon: null }
  const up = diff > 0
  const good = up === props.upIsGood
  return {
    text: formatRupeesCompact(Math.abs(diff)),
    color: good ? 'text-income' : 'text-expense',
    icon: up ? 'arrow_upward' : 'arrow_downward',
    pct: Math.round((Math.abs(diff) * 100) / props.before),
  }
})
</script>

<template>
  <span class="inline-flex items-center justify-end gap-0.5 font-semibold whitespace-nowrap tabular-nums" :class="view.color">
    <AppIcon v-if="view.icon" :name="view.icon" :size="13" />{{ view.text }}
    <span v-if="'pct' in view" class="ml-1 text-xs font-normal text-slate-400">{{ view.pct }}%</span>
  </span>
</template>
