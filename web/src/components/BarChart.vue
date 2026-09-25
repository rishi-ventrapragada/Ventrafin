<script setup lang="ts">
// Month-by-month bars in SVG: grouped (income beside spending) or stacked
// (categories). One rupee axis with hairline gridlines, thin bars with a 2px
// gap between neighbours and stack segments, the chosen month shaded and
// bold, and a tooltip with every value when hovering a month. The same
// numbers are always in a table next to the chart. (Geometry uses floats;
// the money itself stays integer paise.)
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { formatRupeesCompact } from '@/lib/money'
import { formatRupeesAxis, niceAxisStep } from '@/lib/reports'

export interface BarSeries {
  key: string
  name: string
  color: string
  /** Paise per month, in the order of `labels`. */
  values: readonly number[]
}

const props = withDefaults(
  defineProps<{
    labels: readonly string[]
    /** Full month names for the tooltip. */
    titles: readonly string[]
    series: readonly BarSeries[]
    mode?: 'grouped' | 'stacked'
    /** The chosen month, shaded. */
    highlight?: number
    height?: number
    summary: string
  }>(),
  { mode: 'grouped', highlight: -1, height: 220 },
)

const host = ref<HTMLElement | null>(null)
const width = ref(640)
let observer: ResizeObserver | null = null
onMounted(() => {
  if (!host.value) return
  width.value = host.value.clientWidth || 640
  if (typeof ResizeObserver !== 'undefined') {
    observer = new ResizeObserver(([e]) => {
      if (e) width.value = Math.max(280, Math.round(e.contentRect.width))
    })
    observer.observe(host.value)
  }
})
onBeforeUnmount(() => observer?.disconnect())

const AXIS_W = 56
const LABEL_H = 24
const TOP = 8
const GAP = 2

const geometry = computed(() => {
  const n = props.labels.length
  const plotW = Math.max(100, width.value - AXIS_W - 4)
  const plotH = props.height - LABEL_H - TOP
  const totals = props.labels.map((_, i) =>
    props.mode === 'stacked'
      ? props.series.reduce((s, x) => s + (x.values[i] ?? 0), 0)
      : Math.max(0, ...props.series.map((x) => x.values[i] ?? 0)),
  )
  const max = Math.max(0, ...totals)
  const step = niceAxisStep(max)
  const top = Math.max(step, Math.ceil(max / step) * step)
  const y = (v: number) => TOP + plotH - (v / top) * plotH
  const slot = plotW / Math.max(1, n)
  const groupW = Math.min(slot * 0.62, props.mode === 'stacked' ? 44 : 22 * props.series.length)
  const barW = props.mode === 'stacked' ? groupW : (groupW - GAP * (props.series.length - 1)) / Math.max(1, props.series.length)

  const grid: { y: number; label: string }[] = []
  for (let v = 0; v <= top; v += step) grid.push({ y: y(v), label: formatRupeesAxis(v) })

  const bars = props.labels.flatMap((_, i) => {
    const x0 = AXIS_W + i * slot + (slot - groupW) / 2
    if (props.mode === 'grouped') {
      return props.series.map((s, k) => {
        const v = s.values[i] ?? 0
        const h = Math.max(0, y(0) - y(v))
        return { key: `${s.key}-${i}`, x: x0 + k * (barW + GAP), y: y(v), w: barW, h, color: s.color, top: true }
      })
    }
    let acc = 0
    const segs = props.series
      .map((s) => ({ s, v: s.values[i] ?? 0 }))
      .filter((x) => x.v > 0)
      .map(({ s, v }, k, all) => {
        const y1 = y(acc + v)
        const y0 = y(acc)
        acc += v
        // 2px of surface between stacked segments.
        const gap = k < all.length - 1 ? GAP : 0
        return { key: `${s.key}-${i}`, x: x0, y: y1 + gap, w: barW, h: Math.max(0, y0 - y1 - gap), color: s.color, top: k === all.length - 1 }
      })
    return segs
  })

  return {
    plotH,
    slot,
    baseline: y(0),
    grid,
    bars,
    columns: props.labels.map((label, i) => ({ i, label, x: AXIS_W + i * slot, cx: AXIS_W + i * slot + slot / 2 })),
  }
})

const hover = ref<number | null>(null)
const tooltip = computed(() => {
  const i = hover.value
  if (i === null) return null
  const rows = props.series
    .map((s) => ({ name: s.name, color: s.color, value: s.values[i] ?? 0 }))
    .filter((r) => props.mode === 'grouped' || r.value > 0)
  const total = rows.reduce((s, r) => s + r.value, 0)
  const col = geometry.value.columns[i]!
  const left = Math.min(Math.max(col.cx - 90, 0), width.value - 190)
  return { title: props.titles[i] ?? '', rows, total, left }
})
</script>

<template>
  <div ref="host" class="relative w-full" :style="{ height: `${height}px` }">
    <svg :width="width" :height="height" role="img" :aria-label="summary" class="block">
      <!-- the chosen month -->
      <rect
        v-if="highlight >= 0 && geometry.columns[highlight]"
        :x="geometry.columns[highlight]!.x + 2"
        :y="0"
        :width="geometry.slot - 4"
        :height="geometry.baseline"
        rx="4"
        class="fill-primary-soft"
      />
      <g class="text-slate-600">
        <template v-for="g in geometry.grid" :key="g.y">
          <line :x1="56" :x2="width" :y1="g.y" :y2="g.y" stroke="#e2e8f0" stroke-width="1" />
          <text :x="50" :y="g.y + 4" text-anchor="end" font-size="12" fill="currentColor" class="tabular-nums">{{ g.label }}</text>
        </template>
      </g>
      <rect v-for="b in geometry.bars" :key="b.key" :x="b.x" :y="b.y" :width="b.w" :height="b.h" :fill="b.color" :rx="b.top ? 2 : 0" />
      <line :x1="56" :x2="width" :y1="geometry.baseline" :y2="geometry.baseline" stroke="#94a3b8" stroke-width="1" />
      <text
        v-for="c in geometry.columns"
        :key="`l-${c.i}`"
        :x="c.cx"
        :y="height - 7"
        text-anchor="middle"
        font-size="12.5"
        :font-weight="c.i === highlight ? 700 : 400"
        :class="c.i === highlight ? 'fill-primary' : 'fill-slate-700'"
      >
        {{ c.label }}
      </text>
      <!-- hit areas: a whole month column, wider than its bars -->
      <rect
        v-for="c in geometry.columns"
        :key="`h-${c.i}`"
        :x="c.x"
        :y="0"
        :width="geometry.slot"
        :height="height"
        fill="transparent"
        :data-month-col="c.i"
        @mouseenter="hover = c.i"
        @mouseleave="hover = null"
      />
    </svg>
    <div
      v-if="tooltip"
      class="pointer-events-none absolute top-1 z-10 w-[11.5rem] rounded-md border border-slate-200 bg-white px-2.5 py-1.5 text-sm shadow-md"
      :style="{ left: `${tooltip.left}px` }"
      role="tooltip"
    >
      <div class="mb-0.5 font-semibold text-slate-800">{{ tooltip.title }}</div>
      <div v-for="r in tooltip.rows" :key="r.name" class="flex items-center gap-1.5">
        <span class="h-2.5 w-2.5 shrink-0 rounded-sm" :style="{ background: r.color }" />
        <span class="truncate text-slate-700">{{ r.name }}</span>
        <span class="ml-auto font-medium tabular-nums">{{ formatRupeesCompact(r.value) }}</span>
      </div>
      <div v-if="mode === 'stacked' && tooltip.rows.length > 1" class="mt-0.5 flex border-t border-slate-100 pt-0.5 font-semibold">
        Total <span class="ml-auto tabular-nums">{{ formatRupeesCompact(tooltip.total) }}</span>
      </div>
    </div>
  </div>
</template>
