<script setup lang="ts">
// ‹ September 2026 ›, with a month picker on the label.
import Popover from 'primevue/popover'
import { computed, ref } from 'vue'
import { MONTH_SHORT, compareMonths, monthLabel, nextMonth, previousMonth, type YearMonth } from '@/lib/dates'
import AppIcon from './AppIcon.vue'

const props = defineProps<{ max?: YearMonth }>()
const month = defineModel<YearMonth>({ required: true })

const canGoForward = computed(() => !props.max || compareMonths(month.value, props.max) < 0)
const pickerYear = ref(month.value.year)
const popover = ref<InstanceType<typeof Popover> | null>(null)

function toggle(e: Event) {
  pickerYear.value = month.value.year
  popover.value?.toggle(e)
}

function pick(m: number) {
  month.value = { year: pickerYear.value, month: m }
  popover.value?.hide()
}

function isFuture(m: number) {
  return !!props.max && compareMonths({ year: pickerYear.value, month: m }, props.max) > 0
}
</script>

<template>
  <div class="inline-flex items-center rounded-md border border-slate-300 bg-white" data-testid="month-switcher">
    <button type="button" class="px-1.5 py-1 text-slate-600 hover:bg-slate-100" aria-label="Previous month" @click="month = previousMonth(month)">
      <AppIcon name="chevron_left" :size="20" />
    </button>
    <button
      type="button"
      class="inline-flex min-w-[10.5rem] items-center justify-center gap-1.5 border-x border-slate-200 px-2 py-1 font-semibold text-slate-700 hover:bg-slate-50"
      aria-haspopup="dialog"
      data-testid="month-label"
      @click="toggle"
    >
      <AppIcon name="calendar_month" :size="17" class="text-slate-500" />
      {{ monthLabel(month) }}
    </button>
    <button
      type="button"
      class="px-1.5 py-1 text-slate-600 hover:bg-slate-100 disabled:opacity-30"
      aria-label="Next month"
      :disabled="!canGoForward"
      @click="month = nextMonth(month)"
    >
      <AppIcon name="chevron_right" :size="20" />
    </button>
    <Popover ref="popover">
      <div class="w-60">
        <div class="mb-2 flex items-center justify-between">
          <button type="button" class="rounded p-1 hover:bg-slate-100" aria-label="Previous year" @click="pickerYear--">
            <AppIcon name="chevron_left" :size="18" />
          </button>
          <span class="font-semibold">{{ pickerYear }}</span>
          <button type="button" class="rounded p-1 hover:bg-slate-100" aria-label="Next year" @click="pickerYear++">
            <AppIcon name="chevron_right" :size="18" />
          </button>
        </div>
        <div class="grid grid-cols-4 gap-1">
          <button
            v-for="(name, i) in MONTH_SHORT"
            :key="name"
            type="button"
            class="rounded py-1.5 text-sm disabled:opacity-30"
            :class="month.year === pickerYear && month.month === i + 1 ? 'bg-ocean text-white' : 'hover:bg-slate-100'"
            :disabled="isFuture(i + 1)"
            @click="pick(i + 1)"
          >
            {{ name }}
          </button>
        </div>
      </div>
    </Popover>
  </div>
</template>
