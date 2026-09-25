// PrimeVue setup shared by the app, the component tests and the demo page.
import { definePreset } from '@primeuix/themes'
import Aura from '@primeuix/themes/aura'
import PrimeVue from 'primevue/config'
import ConfirmationService from 'primevue/confirmationservice'
import ToastService from 'primevue/toastservice'
import Tooltip from 'primevue/tooltip'
import type { App } from 'vue'
import { OCEAN_PRIMARY_SCALE } from './lib/theme'

/** Aura with the Ocean blue (#1565C0, Material Blue 800) as the primary colour. */
export const OceanPreset = definePreset(Aura, {
  semantic: {
    primary: OCEAN_PRIMARY_SCALE,
    colorScheme: {
      light: {
        primary: {
          color: '{primary.800}',
          contrastColor: '#ffffff',
          hoverColor: '{primary.900}',
          activeColor: '{primary.900}',
        },
        highlight: {
          background: '{primary.50}',
          focusBackground: '{primary.100}',
          color: '{primary.800}',
          focusColor: '{primary.900}',
        },
      },
    },
  },
})

export function installUi(app: App): void {
  app.use(PrimeVue, {
    theme: {
      preset: OceanPreset,
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
