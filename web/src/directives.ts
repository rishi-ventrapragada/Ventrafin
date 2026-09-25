import type { Directive } from 'vue'

/** Focuses (and selects) an editor as soon as it appears, like Excel's edit mode. */
export const vFocus: Directive<HTMLInputElement> = {
  mounted(el) {
    el.focus()
    el.select?.()
  },
}

/**
 * `@keydown` on a dialog's <form>: Enter in any of its fields submits it, as
 * the Enter key does in a desktop program. Browsers only do this for text
 * boxes; this also covers radio buttons, checkboxes and drop-downs, and
 * treats them all the same. Enter keeps its own meaning in a textarea (a new
 * line), on a button (press it), on a link, and in an open pick list.
 * Submits through the form's submit button, and not while that is disabled.
 */
export function submitOnEnter(e: KeyboardEvent): void {
  if (e.key !== 'Enter' || e.defaultPrevented || e.isComposing || e.shiftKey || e.ctrlKey || e.altKey || e.metaKey) return
  const target = e.target
  if (!(target instanceof HTMLElement) || !(e.currentTarget instanceof HTMLFormElement)) return
  if (
    target instanceof HTMLTextAreaElement ||
    target instanceof HTMLButtonElement ||
    target instanceof HTMLAnchorElement ||
    target.isContentEditable ||
    target.getAttribute('aria-expanded') === 'true'
  ) {
    return
  }
  const form = e.currentTarget
  // The primary button may sit in the dialog's footer, outside the <form>, tied to it by form="…".
  const submitter = [...form.elements].find((el): el is HTMLButtonElement => el instanceof HTMLButtonElement && el.type === 'submit')
  e.preventDefault()
  if (submitter?.disabled) return
  form.requestSubmit(submitter)
}
