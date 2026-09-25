// Reading a CSV file for import (PRD § 4.9). A file goes through the same
// column detection (paste.ts) and row parser (entryRow.ts) as rows pasted
// from Excel, so both are validated identically. This module only turns the
// file's bytes into rows of cells.
import { readTable, splitDelimited, type PasteTable } from './paste'

/** Larger files are refused before parsing (a year of daily entries is well under 1 MB). */
export const MAX_IMPORT_BYTES = 5 * 1024 * 1024

/** Most data rows one import may hold; larger files should be split. */
export const MAX_IMPORT_ROWS = 5000

/**
 * The file's text. UTF-8 is expected ("CSV UTF-8" in Excel, and Ventrafin's
 * own export); a leading byte-order mark is dropped. Excel's plain "CSV"
 * is saved in the PC's Windows code page instead, so bytes that aren't valid
 * UTF-8 are read as Windows-1252 (the ₹ sign can't survive that format, but
 * letters, digits and commas do).
 */
export function decodeCsvBytes(bytes: Uint8Array): string {
  let text: string
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    text = new TextDecoder('windows-1252').decode(bytes)
  }
  return text.replace(/^﻿/, '')
}

/**
 * Comma, semicolon (Excel's CSV where the decimal separator is a comma) or
 * tab: whichever appears most in the first line, outside quotes.
 */
export function detectSeparator(text: string): ',' | ';' | '\t' {
  const counts = { ',': 0, ';': 0, '\t': 0 }
  let inQuotes = false
  for (const ch of text) {
    if (ch === '"') inQuotes = !inQuotes
    else if (!inQuotes && (ch === '\n' || ch === '\r')) {
      if (counts[','] + counts[';'] + counts['\t'] > 0) break
    } else if (!inQuotes && (ch === ',' || ch === ';' || ch === '\t')) counts[ch]++
  }
  if (counts['\t'] > counts[','] && counts['\t'] >= counts[';']) return '\t'
  if (counts[';'] > counts[',']) return ';'
  return ','
}

/**
 * Spreadsheet exports (Ventrafin's included) put an apostrophe before a cell
 * that starts with = + - or @ so it isn't run as a formula. Take it off
 * again: `'-5 discount` -> `-5 discount`.
 */
export function stripFormulaGuard(cell: string): string {
  return /^'[=+\-@]/.test(cell) ? cell.slice(1) : cell
}

/** The file's rows of cells, with the heading row detected. */
export function readCsv(text: string, today: string): PasteTable {
  const cells = splitDelimited(text, detectSeparator(text)).map((row) => row.map(stripFormulaGuard))
  return readTable(cells, today)
}

/** Why a chosen file can't be imported, or null if it can be read. */
export function fileProblem(file: { name: string; size: number }): string | null {
  const name = file.name.toLowerCase()
  if (/\.(xlsx|xlsm|xls|ods|numbers)$/.test(name)) {
    return 'This is a spreadsheet file, not CSV. In Excel choose File › Save As › "CSV UTF-8 (Comma delimited)", then import that file. Or copy the rows and use Paste from Excel on the Add page.'
  }
  if (file.size === 0) return 'The file is empty.'
  if (file.size > MAX_IMPORT_BYTES) return 'The file is larger than 5 MB. Split it into smaller files (for example one per year) and import them one at a time.'
  return null
}
