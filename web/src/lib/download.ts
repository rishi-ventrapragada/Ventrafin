// Saving a file the app made (the CSV export) to the PC's Downloads folder.

/** Excel only reads a CSV as UTF-8 (₹, Hindi text) when it starts with this. */
export const UTF8_BOM = '﻿'

/** Starts a download of `text` as `name`, with the byte-order mark Excel needs. */
export function downloadCsv(name: string, text: string): void {
  const url = URL.createObjectURL(new Blob([UTF8_BOM, text], { type: 'text/csv;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.style.display = 'none'
  document.body.append(a)
  a.click()
  a.remove()
  // Revoked later: some browsers read the blob after click() returns.
  setTimeout(() => URL.revokeObjectURL(url), 30_000)
}
