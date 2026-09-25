<script setup lang="ts">
// A donut in category colours, with the category icon on slices of 8 % or
// more, and the total in the middle: the phone's dashboard donut, as SVG.
// (Geometry only uses floats; the money itself stays integer paise.)
import { computed } from 'vue'
import { foregroundOn } from '@/lib/categoryStyle'
import { FILLED_ICONS, OUTLINED_ICONS } from '@/lib/icons.generated'

interface DonutSegment {
  value: number
  color: string
  icon: string
  label: string
}

const props = withDefaults(
  defineProps<{ segments: readonly DonutSegment[]; size?: number; thickness?: number; centerLabel?: string; centerValue?: string }>(),
  { size: 196, thickness: 34, centerLabel: '', centerValue: '' },
)

const GAP_DEGREES = 1.2
const ICON_SHARE = 0.08

const geometry = computed(() => {
  const total = props.segments.reduce((s, x) => s + x.value, 0)
  const r = (props.size - props.thickness) / 2
  const c = props.size / 2
  const circumference = 2 * Math.PI * r
  const gap = props.segments.length > 1 ? (GAP_DEGREES / 360) * circumference : 0
  let offset = 0
  const arcs = props.segments
    .filter((s) => s.value > 0)
    .map((s) => {
      const share = total > 0 ? s.value / total : 0
      const length = share * circumference
      const mid = ((offset + length / 2) / circumference) * 2 * Math.PI - Math.PI / 2
      const arc = {
        ...s,
        share,
        dash: `${Math.max(0, length - gap)} ${circumference}`,
        dashOffset: -offset,
        iconX: c + r * Math.cos(mid),
        iconY: c + r * Math.sin(mid),
        path: FILLED_ICONS[s.icon] ?? OUTLINED_ICONS[s.icon] ?? FILLED_ICONS.label,
      }
      offset += length
      return arc
    })
  return { r, c, arcs }
})

const iconSize = computed(() => Math.round(props.thickness * 0.58))
</script>

<template>
  <div class="relative shrink-0" :style="{ width: `${size}px`, height: `${size}px` }">
    <svg :width="size" :height="size" :viewBox="`0 0 ${size} ${size}`" role="img" :aria-label="`${centerLabel} ${centerValue}`">
      <circle :cx="geometry.c" :cy="geometry.c" :r="geometry.r" fill="none" stroke="#eef2f6" :stroke-width="thickness" />
      <g :transform="`rotate(-90 ${geometry.c} ${geometry.c})`">
        <circle
          v-for="a in geometry.arcs"
          :key="a.label"
          :cx="geometry.c"
          :cy="geometry.c"
          :r="geometry.r"
          fill="none"
          :stroke="a.color"
          :stroke-width="thickness"
          :stroke-dasharray="a.dash"
          :stroke-dashoffset="a.dashOffset"
        >
          <title>{{ a.label }}: {{ Math.round(a.share * 100) }}%</title>
        </circle>
      </g>
      <template v-for="a in geometry.arcs" :key="`icon-${a.label}`">
        <svg
          v-if="a.share >= ICON_SHARE"
          :x="a.iconX - iconSize / 2"
          :y="a.iconY - iconSize / 2"
          :width="iconSize"
          :height="iconSize"
          viewBox="0 -960 960 960"
          aria-hidden="true"
        >
          <path :d="a.path" :fill="foregroundOn(a.color)" />
        </svg>
      </template>
    </svg>
    <div class="pointer-events-none absolute inset-0 flex flex-col items-center justify-center text-center">
      <span class="text-sm font-medium text-slate-600">{{ centerLabel }}</span>
      <span class="text-lg leading-tight font-bold text-expense tabular-nums">{{ centerValue }}</span>
    </div>
  </div>
</template>
