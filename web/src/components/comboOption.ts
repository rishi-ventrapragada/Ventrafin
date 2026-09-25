/** One choice in a ComboInput. The label is also the cell's value. */
export interface ComboOption {
  label: string
  /** Other words that find this option ("gpay" for UPI). */
  keywords?: readonly string[]
  /** Small grey text on the right of the list row. */
  hint?: string
}

const norm = (s: string) => s.trim().toLowerCase().replace(/\s+/g, ' ')

/** Options whose label (or a keyword) starts with the query first, then those containing it. */
export function filterOptions<T extends ComboOption>(options: readonly T[], query: string): T[] {
  const q = norm(query)
  if (!q) return [...options]
  const starts: T[] = []
  const contains: T[] = []
  for (const o of options) {
    const words = [o.label, ...(o.keywords ?? [])].map(norm)
    if (words.some((w) => w.startsWith(q))) starts.push(o)
    else if (words.some((w) => w.includes(q))) contains.push(o)
  }
  return [...starts, ...contains]
}

/** The option typed text stands for: an exact label/keyword, or the only one it starts. */
export function resolveOption<T extends ComboOption>(options: readonly T[], text: string): T | null {
  const q = norm(text)
  if (!q) return null
  const exact = options.find((o) => [o.label, ...(o.keywords ?? [])].some((w) => norm(w) === q))
  if (exact) return exact
  const starting = options.filter((o) => [o.label, ...(o.keywords ?? [])].some((w) => norm(w).startsWith(q)))
  return starting.length === 1 ? starting[0]! : null
}
