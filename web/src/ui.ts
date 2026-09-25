// PrimeVue setup shared by the app, the component tests and the demo page.
import PrimeVue from 'primevue/config'
import ConfirmationService from 'primevue/confirmationservice'
import ToastService from 'primevue/toastservice'
import Tooltip from 'primevue/tooltip'
import type { App } from 'vue'
import { applyTheme, initialTheme, presetFor } from './lib/theme'

export function installUi(app: App): void {
  // Open in the theme this browser showed last; the profile's theme is
  // applied as soon as it loads (DECISIONS.md D22).
  const theme = initialTheme()
  applyTheme(theme, { preset: false })
  app.use(PrimeVue, {
    theme: {
      preset: presetFor(theme),
      options: {
        // Light mode only (PRD § 4.8).
        darkModeSelector: false,
        cssLayer: { name: 'primevue', order: 'theme, base, primevue, components, utilities' },
      },
    },
  })
  app.use(ToastService)
  app.use(ConfirmationService)
  app.directive('tooltip', Tooltip)
}
