// Sign out after asking, the same from the sidebar and from Settings (and
// the same question as the phone). Cancel has the focus, so a stray Enter
// keeps Dad signed in.
import type { ConfirmationOptions } from 'primevue/confirmationoptions'
import { useConfirm } from 'primevue/useconfirm'
import { useApp } from '@/data/appContext'
import { describeError } from '@/lib/errors'
import { useNotify } from './useNotify'

export const SIGN_OUT_CONFIRM: ConfirmationOptions = {
  header: 'Sign out?',
  message: 'Your data stays in your account. Sign in with Google to come back. The phone stays signed in.',
  acceptLabel: 'Sign out',
  rejectLabel: 'Cancel',
  defaultFocus: 'reject',
  rejectProps: { severity: 'secondary', outlined: true },
}

export function useSignOut(): () => void {
  const app = useApp()
  const confirm = useConfirm()
  const notify = useNotify()
  return () =>
    confirm.require({
      ...SIGN_OUT_CONFIRM,
      accept: async () => {
        try {
          await app.auth.signOut()
        } catch (e) {
          notify.error('Sign-out failed', describeError(e))
        }
      },
    })
}
