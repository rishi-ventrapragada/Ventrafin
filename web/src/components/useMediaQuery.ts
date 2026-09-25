// A CSS media query as a reactive boolean, following the window as it is
// resized (or moved to another screen).
import { onBeforeUnmount, ref, type Ref } from 'vue'

export function useMediaQuery(query: string): Ref<boolean> {
  const mql = typeof window !== 'undefined' && window.matchMedia ? window.matchMedia(query) : null
  const matches = ref(mql?.matches ?? false)
  const onChange = (e: MediaQueryListEvent) => (matches.value = e.matches)
  mql?.addEventListener('change', onChange)
  onBeforeUnmount(() => mql?.removeEventListener('change', onChange))
  return matches
}
