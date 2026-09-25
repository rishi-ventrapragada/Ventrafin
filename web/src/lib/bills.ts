// Bill wording and looks, the same as the phone (mobile/lib/features/bills/
// bill_visuals.dart). Due dates and status come from Postgres
// (get_bill_schedule); nothing here computes them.
import { UNCATEGORIZED_INK } from './theme'
import { MONTH_SHORT, isoParts } from './dates'
import type { AccountType, Bill, BillStatus, PaymentMethod } from './models'

/** "Overdue · 5 days", "Due today", "Due in 3 days", "Due 10 Oct". */
export function billStatusLabel(b: Pick<Bill, 'status' | 'daysUntil' | 'overdueCount' | 'nextDueDate'>): string {
  switch (b.status) {
    case 'overdue': {
      if (b.overdueCount > 1) return `Overdue · ${b.overdueCount} months`
      const days = -b.daysUntil
      return `Overdue · ${days} ${days === 1 ? 'day' : 'days'}`
    }
    case 'due_today':
      return 'Due today'
    case 'due_soon':
      return b.daysUntil === 1 ? 'Due tomorrow' : `Due in ${b.daysUntil} days`
    default: {
      const { month, day } = isoParts(b.nextDueDate)
      return `Due ${day} ${MONTH_SHORT[month - 1]}`
    }
  }
}

/** Red for overdue, amber within a week, grey otherwise; text is 4.5:1 or better on its tint. */
export function billStatusLook(s: BillStatus): { fg: string; bg: string; icon: string } {
  switch (s) {
    case 'overdue':
      return { fg: '#B71C1C', bg: '#FDECEA', icon: 'error' }
    case 'due_today':
    case 'due_soon':
      return { fg: UNCATEGORIZED_INK, bg: '#FFF3D6', icon: 'schedule' }
    default:
      return { fg: '#455A64', bg: '#EFF2F4', icon: 'event' }
  }
}

/** `10th of every month`; 31 reads as the last day. */
export function dueDayLabel(day: number): string {
  if (day >= 31) return 'last day of every month'
  const suffix = day >= 11 && day <= 13 ? 'th' : (['th', 'st', 'nd', 'rd'][day % 10] ?? 'th')
  return `${day}${suffix} of every month`
}

/** A sensible "paid by" for a payment from `type` of account. */
export function defaultMethodFor(type: AccountType | undefined): PaymentMethod {
  return type === 'cash' ? 'cash' : type === 'credit' ? 'card' : 'upi'
}

/** Why `name` can't be a bill name, or null. */
export function billNameError(name: string, max = 60): string | null {
  const n = name.trim()
  if (!n) return 'Enter a name, like "BESCOM electricity" or "Home loan EMI"'
  if ([...n].length > max) return `Keep it to ${max} characters or fewer`
  return null
}
