import type { Directive } from 'vue'

/** Focuses (and selects) an editor as soon as it appears, like Excel's edit mode. */
export const vFocus: Directive<HTMLInputElement> = {
  mounted(el) {
    el.focus()
    el.select?.()
  },
}
