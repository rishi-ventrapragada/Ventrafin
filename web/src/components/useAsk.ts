// Confirm dialogs as a promise (true = the accept button), for code that has
// to wait for the answer: a route-leave guard, or a form dialog asking before
// it closes. `asking` is true while one is open, so the form dialog behind it
// ignores the Escape that closes the question.
import type { ConfirmationOptions } from 'primevue/confirmationoptions'
import { useConfirm } from 'primevue/useconfirm'
import { ref } from 'vue'

/** Leaving a form with typed, unsaved changes (same wording as the phone). */
export const DISCARD_CHANGES: ConfirmationOptions = {
  header: 'Discard changes?',
  message: "What you typed hasn't been saved.",
  acceptLabel: 'Discard',
  rejectLabel: 'Keep editing',
  // Enter or a stray click keeps the typing.
  defaultFocus: 'reject',
  acceptProps: { severity: 'danger', outlined: true },
  rejectProps: { severity: 'secondary' },
}

export function useAsk() {
  const confirm = useConfirm()
  const asking = ref(false)

  function ask(options: Omit<ConfirmationOptions, 'accept' | 'reject' | 'onHide'>): Promise<boolean> {
    asking.value = true
    return new Promise((resolve) => {
      const done = (answer: boolean) => {
        asking.value = false
        resolve(answer)
      }
      confirm.require({ ...options, accept: () => done(true), reject: () => done(false), onHide: () => done(false) })
    })
  }

  return { ask, asking }
}

/**
 * For a form in a Dialog: closing it with X or Escape asks "Discard
 * changes?" first when something was typed (`dirty`), and does nothing
 * while another question is open. `close` really closes it.
 */
export function useGuardedClose(dirty: () => boolean, close: () => void) {
  const { ask, asking } = useAsk()
  async function requestClose() {
    if (asking.value) return
    if (!dirty() || (await ask(DISCARD_CHANGES))) close()
  }
  return { requestClose, ask, asking }
}
