// jsdom lacks a few browser APIs that PrimeVue and the grid use.
import { afterEach } from 'vitest'
import { unmountAll } from './support/mountApp'

if (!window.matchMedia) {
  window.matchMedia = (query: string) =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList
}

if (!('ResizeObserver' in window)) {
  ;(window as unknown as { ResizeObserver: unknown }).ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
}

if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => {}

afterEach(() => {
  unmountAll()
  document.body.innerHTML = ''
  localStorage.clear()
  sessionStorage.clear()
})
