// Toast messages, with one rule for the whole web app: an error stays until
// it is closed, so it can't vanish before it's read; confirmations, notes and
// warnings go away by themselves. Pages call these instead of useToast().
import type { ToastMessageOptions } from 'primevue/toast'
import { useToast } from 'primevue/usetoast'

/** How long each kind of message stays up, in milliseconds. Errors have no entry: they stay. */
export const TOAST_LIFE = { success: 4000, info: 5000, warn: 6000 } as const

export type NotifySeverity = 'success' | 'info' | 'warn' | 'error'

export interface NotifyOptions {
  detail?: string
  /** Only for timed messages: a longer or shorter time than the usual one. */
  life?: number
  /** A separate <Toast group>, e.g. the Transactions "Deleted … Undo". */
  group?: string
}

/** The message PrimeVue shows: an error without a `life` (sticky), anything else timed. */
export function toastMessage(severity: NotifySeverity, summary: string, opts: NotifyOptions = {}): ToastMessageOptions {
  const message: ToastMessageOptions = { severity, summary }
  if (opts.detail !== undefined) message.detail = opts.detail
  if (opts.group !== undefined) message.group = opts.group
  if (severity !== 'error') message.life = opts.life ?? TOAST_LIFE[severity]
  return message
}

export function useNotify() {
  const toast = useToast()
  const show = (severity: NotifySeverity) => (summary: string, opts?: NotifyOptions) => toast.add(toastMessage(severity, summary, opts))
  return {
    success: show('success'),
    info: show('info'),
    warn: show('warn'),
    /** Stays until closed. `detail` is usually describeError(e). */
    error: (summary: string, detail?: string) => toast.add(toastMessage('error', summary, { detail })),
    removeGroup: (group: string) => toast.removeGroup(group),
  }
}
