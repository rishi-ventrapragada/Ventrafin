<script setup lang="ts" generic="T extends ComboOption">
// A text cell with a pick list, for spreadsheet-style entry (category,
// account, type, paid by). Typing filters the list; Enter or Tab takes the
// highlighted option; Alt+Down or F4 opens it; Esc puts the old value back.
// Plain Up/Down/Enter are left to the grid (Excel moves between rows), so
// the list only takes them while it is open.
//
// The value is the option's label, like a spreadsheet cell. Text that
// matches no option is kept as typed (the row validator flags it), so a
// pasted "Kirana" isn't silently thrown away.
import { computed, nextTick, onBeforeUnmount, onMounted, ref, useId, watch } from 'vue'
import type { ComboOption } from './comboOption'
import { filterOptions, resolveOption } from './comboOption'
import AppIcon from './AppIcon.vue'

const props = withDefaults(
  defineProps<{
    modelValue: string
    options: readonly T[]
    placeholder?: string
    disabled?: boolean
    invalid?: boolean
    warning?: boolean
    ariaLabel?: string
    autofocus?: boolean
    /** Extra attributes for the <input> (e.g. data-row / data-col for grid navigation). */
    inputAttrs?: Record<string, string | number>
  }>(),
  {
    placeholder: '',
    disabled: false,
    invalid: false,
    warning: false,
    ariaLabel: undefined,
    autofocus: false,
    inputAttrs: () => ({}),
  },
)

const emit = defineEmits<{
  'update:modelValue': [value: string]
  /** The user finished with the cell (picked an option or left it). */
  commit: [value: string]
}>()

defineSlots<{
  /** Shown inside the cell, before the text (e.g. the chosen category's icon). */
  prefix?: () => unknown
  /** One row of the pick list. */
  option?: (props: { option: T }) => unknown
}>()

const listId = useId()
const input = ref<HTMLInputElement | null>(null)
const text = ref(props.modelValue)
const open = ref(false)
const highlight = ref(0)
const typed = ref(false)
const popupStyle = ref<Record<string, string>>({})

watch(
  () => props.modelValue,
  (v) => {
    if (!typed.value) text.value = v
  },
)

const filtered = computed(() => (typed.value ? filterOptions(props.options, text.value) : props.options))

function place() {
  const el = input.value?.closest('[data-combo]') ?? input.value
  if (!el) return
  const r = el.getBoundingClientRect()
  const below = window.innerHeight - r.bottom
  const up = below < 220 && r.top > below
  popupStyle.value = {
    position: 'fixed',
    left: `${Math.round(r.left)}px`,
    minWidth: `${Math.max(180, Math.round(r.width))}px`,
    ...(up ? { bottom: `${Math.round(window.innerHeight - r.top + 2)}px` } : { top: `${Math.round(r.bottom + 2)}px` }),
  }
}

function openList(all = false) {
  if (props.disabled) return
  if (all) typed.value = false
  place()
  open.value = true
  const current = filtered.value.findIndex((o) => o.label === props.modelValue)
  highlight.value = Math.max(0, current)
  void scrollHighlightIntoView()
}

function close() {
  open.value = false
}

function commitText(value: string) {
  typed.value = false
  text.value = value
  if (value !== props.modelValue) emit('update:modelValue', value)
  emit('commit', value)
}

function choose(option: T) {
  commitText(option.label)
  close()
}

async function scrollHighlightIntoView() {
  await nextTick()
  document.getElementById(`${listId}-${highlight.value}`)?.scrollIntoView({ block: 'nearest' })
}

function move(step: number) {
  const n = filtered.value.length
  if (n === 0) return
  highlight.value = (highlight.value + step + n) % n
  void scrollHighlightIntoView()
}

function onInput(e: Event) {
  text.value = (e.target as HTMLInputElement).value
  typed.value = true
  if (!open.value) openList()
  highlight.value = 0
}

function onKeydown(e: KeyboardEvent) {
  switch (e.key) {
    case 'ArrowDown':
    case 'ArrowUp':
      if (open.value) {
        e.preventDefault()
        e.stopPropagation()
        move(e.key === 'ArrowDown' ? 1 : -1)
      } else if (e.altKey) {
        e.preventDefault()
        e.stopPropagation()
        openList(true)
      }
      break
    case 'F4':
      e.preventDefault()
      if (open.value) close()
      else openList(true)
      break
    case 'Enter': {
      // Take the highlighted option, then let the grid move down / the table finish editing.
      const option = open.value ? filtered.value[highlight.value] : undefined
      if (option) choose(option)
      else if (typed.value) finishTyping()
      break
    }
    case 'Tab': {
      const option = open.value && typed.value ? filtered.value[highlight.value] : undefined
      if (option) choose(option)
      else if (typed.value) finishTyping()
      close()
      break
    }
    case 'Escape':
      if (open.value || typed.value) {
        e.preventDefault()
        e.stopPropagation()
        typed.value = false
        text.value = props.modelValue
        close()
      }
      break
  }
}

/** Leaving the cell with typed text: the matching option, else the text as typed. */
function finishTyping() {
  const match = resolveOption(props.options, text.value)
  commitText(match ? match.label : text.value.trim())
}

function onBlur() {
  if (typed.value) finishTyping()
  close()
}

function onFocus() {
  // Excel-like: arriving in a cell selects its content, so typing replaces it.
  input.value?.select()
}

function onOptionDown(e: MouseEvent, option: T) {
  // mousedown, not click: keeps focus in the cell and wins the race with
  // anything that reacts to the input losing focus.
  e.preventDefault()
  choose(option)
}

function toggleFromButton(e: MouseEvent) {
  e.preventDefault()
  input.value?.focus()
  if (open.value) close()
  else openList(true)
}

onMounted(() => {
  // Table cell editors appear on click: take the focus straight away.
  if (props.autofocus) input.value?.focus()
})

const reposition = () => open.value && place()
watch(open, (isOpen) => {
  if (isOpen) {
    window.addEventListener('scroll', reposition, true)
    window.addEventListener('resize', reposition)
  } else {
    window.removeEventListener('scroll', reposition, true)
    window.removeEventListener('resize', reposition)
  }
})
onBeforeUnmount(() => {
  window.removeEventListener('scroll', reposition, true)
  window.removeEventListener('resize', reposition)
})

defineExpose({ focus: () => input.value?.focus(), input })
</script>

<template>
  <div
    data-combo
    class="flex h-full w-full min-w-0 items-center gap-1.5"
    :class="{ 'opacity-50': disabled }"
  >
    <slot name="prefix" />
    <input
      ref="input"
      type="text"
      role="combobox"
      autocomplete="off"
      spellcheck="false"
      class="h-full min-w-0 flex-1 bg-transparent outline-none"
      :value="text"
      :placeholder="placeholder"
      :disabled="disabled"
      :autofocus="autofocus"
      :aria-label="ariaLabel"
      :aria-invalid="invalid || undefined"
      :aria-expanded="open"
      :aria-controls="listId"
      :aria-activedescendant="open ? `${listId}-${highlight}` : undefined"
      v-bind="inputAttrs"
      @input="onInput"
      @keydown="onKeydown"
      @focus="onFocus"
      @blur="onBlur"
    />
    <button
      v-if="!disabled"
      type="button"
      tabindex="-1"
      class="shrink-0 rounded text-slate-400 hover:text-slate-700"
      aria-label="Show choices"
      @mousedown="toggleFromButton"
    >
      <AppIcon name="expand_more" :size="16" />
    </button>
    <Teleport to="body">
      <ul
        v-if="open && filtered.length > 0"
        :id="listId"
        role="listbox"
        data-pc-section="overlay"
        class="z-[2000] max-h-64 overflow-auto rounded-md border border-slate-300 bg-white py-1 text-[0.93rem] shadow-lg"
        :style="popupStyle"
      >
        <li
          v-for="(option, i) in filtered"
          :id="`${listId}-${i}`"
          :key="option.label"
          role="option"
          :aria-selected="i === highlight"
          class="flex cursor-pointer items-center gap-2 px-2.5 py-1 whitespace-nowrap"
          :class="i === highlight ? 'bg-blue-50 text-slate-900' : 'text-slate-700'"
          @mousedown="onOptionDown($event, option)"
          @mousemove="highlight = i"
        >
          <slot name="option" :option="option">{{ option.label }}</slot>
          <span v-if="option.hint" class="ml-auto pl-3 text-xs text-slate-400">{{ option.hint }}</span>
        </li>
      </ul>
    </Teleport>
  </div>
</template>
