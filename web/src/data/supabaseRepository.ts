import type { RealtimeChannel } from '@supabase/supabase-js'
import { monthStart, nextMonth, type YearMonth } from '@/lib/dates'
import { AppError, toAppError } from '@/lib/errors'
import {
  accountFromRow,
  accountTotalsFromRow,
  billDraftToRow,
  billFromRow,
  categoryFromRow,
  comparisonFromRow,
  draftToRow,
  monthlyCategoryTotalFromRow,
  monthlyTotalFromRow,
  monthOfRow,
  monthTotalsFromRow,
  patchToRow,
  profileFromRow,
  txnFromRow,
  type AccountType,
  type BillDraft,
  type CategoryKind,
  type PaymentMethod,
  type Txn,
  type TxnPatch,
} from '@/lib/models'
import {
  REALTIME_TABLES,
  type CategoryEdit,
  type DataChange,
  type FinanceRepository,
  type LiveStatus,
  type NewTxn,
} from './repository'
import type { Database } from '@/lib/database.types'
import type { AppSupabaseClient } from './supabaseClient'

type Result<T> = { data: T | null; error: { message: string; code?: string } | null }

async function run<T>(request: PromiseLike<Result<T>>): Promise<T> {
  let result: Result<T>
  try {
    result = await request
  } catch (e) {
    // fetch itself threw (offline, timeout): postgrest-js normally reports
    // these as { error }, but be safe.
    throw new AppError(e instanceof Error ? e.message : String(e), null, true)
  }
  if (result.error) throw toAppError(result.error)
  return result.data as T
}

const TXN_COLUMNS =
  'id, date, amount_paise, description, type, account_id, to_account_id, category_id, payment_method, auto_categorized, owner_id, created_at, updated_at'

const ACCOUNT_COLUMNS = 'id, name, type, archived'
const CATEGORY_COLUMNS = 'id, name, kind, color, archived, icon'

/** Supabase's default "max rows" per API response. */
const TXN_PAGE = 1000

export class SupabaseFinanceRepository implements FinanceRepository {
  constructor(private readonly client: AppSupabaseClient) {}

  async fetchAccounts() {
    const rows = await run(this.client.from('accounts').select(ACCOUNT_COLUMNS).order('name'))
    return rows.map(accountFromRow)
  }

  async insertAccount(id: string, name: string, type: AccountType) {
    let row
    try {
      row = await run(this.client.from('accounts').insert({ id, name: name.trim(), type }).select(ACCOUNT_COLUMNS).maybeSingle())
    } catch (e) {
      // An earlier attempt with this id already went through (its response was lost).
      if (!(e instanceof AppError && e.code === '23505' && /pkey/.test(e.message))) throw e
      row = await run(this.client.from('accounts').select(ACCOUNT_COLUMNS).eq('id', id).maybeSingle())
    }
    if (!row) throw new AppError('insertAccount returned no row')
    return accountFromRow(row)
  }

  async updateAccount(id: string, name: string, type: AccountType) {
    const row = await run(
      this.client.from('accounts').update({ name: name.trim(), type }).eq('id', id).select(ACCOUNT_COLUMNS).maybeSingle(),
    )
    if (!row) throw new AppError('Account not found', 'PGRST116')
    return accountFromRow(row)
  }

  async setAccountArchived(id: string, archived: boolean) {
    await run(this.client.from('accounts').update({ archived }).eq('id', id).select('id').single())
  }

  async fetchCategories() {
    const rows = await run(this.client.from('categories').select(CATEGORY_COLUMNS).order('name'))
    return rows.map(categoryFromRow)
  }

  async fetchTransactions(month: YearMonth) {
    const rows = await run(
      this.client
        .from('transactions')
        .select(TXN_COLUMNS)
        .gte('date', monthStart(month))
        .lt('date', monthStart(nextMonth(month)))
        .order('date', { ascending: false })
        .order('created_at', { ascending: false }),
    )
    return rows.map(txnFromRow)
  }

  async fetchMonthTotals(month: YearMonth) {
    const rows = await run(this.client.rpc('get_month_totals', { p_month: monthStart(month) }))
    const first = rows[0]
    if (!first) throw new AppError('get_month_totals returned no row')
    return monthTotalsFromRow(first)
  }

  async fetchMonthComparison(month: YearMonth) {
    const rows = await run(this.client.rpc('get_month_comparison', { p_month: monthStart(month) }))
    return rows.map(comparisonFromRow)
  }

  async insertTransactions(rows: readonly NewTxn[]): Promise<Txn[]> {
    if (rows.length === 0) return []
    const ids = rows.map((r) => r.id)
    try {
      const inserted = await run(
        this.client
          .from('transactions')
          .insert(rows.map((r) => ({ id: r.id, ...draftToRow(r) })))
          .select(TXN_COLUMNS),
      )
      return this.inOrder(ids, inserted.map(txnFromRow))
    } catch (e) {
      // 23505 on the primary key: an earlier attempt with these ids already
      // went through (its response was lost). The insert is one statement,
      // so it is all or nothing: fetch the rows and treat them as saved.
      if (e instanceof AppError && e.code === '23505') {
        const existing = await run(this.client.from('transactions').select(TXN_COLUMNS).in('id', ids))
        if (existing.length === ids.length) return this.inOrder(ids, existing.map(txnFromRow))
      }
      throw e
    }
  }

  private inOrder(ids: readonly string[], txns: Txn[]): Txn[] {
    const byId = new Map(txns.map((t) => [t.id, t]))
    return ids.map((id) => byId.get(id)).filter((t): t is Txn => t !== undefined)
  }

  async updateTransaction(id: string, patch: TxnPatch) {
    const row = await run(this.client.from('transactions').update(patchToRow(patch)).eq('id', id).select(TXN_COLUMNS).maybeSingle())
    // No row back: it was deleted (e.g. on the phone) or isn't ours.
    if (!row) throw new AppError('Transaction not found', 'PGRST116')
    return txnFromRow(row)
  }

  async deleteTransactions(ids: readonly string[]) {
    if (ids.length === 0) return 0
    // .select() makes a no-op delete (already gone) visible instead of silently "succeeding".
    const deleted = await run(this.client.from('transactions').delete().in('id', [...ids]).select('id'))
    return deleted.length
  }

  async fetchTransactionsBetween(from: string, to: string) {
    const all: Txn[] = []
    // The API returns at most TXN_PAGE rows per request (Supabase's max rows).
    for (let offset = 0; ; offset += TXN_PAGE) {
      const rows = await run(
        this.client
          .from('transactions')
          .select(TXN_COLUMNS)
          .gte('date', from)
          .lte('date', to)
          .order('date')
          .order('id')
          .range(offset, offset + TXN_PAGE - 1),
      )
      all.push(...rows.map(txnFromRow))
      if (rows.length < TXN_PAGE) return all
    }
  }

  async exportTransactionsCsv(args: { from: string | null; to: string | null; ids?: readonly string[] }) {
    const csv = await run(
      this.client.rpc('export_transactions_csv', {
        ...(args.from ? { p_from: args.from } : {}),
        ...(args.to ? { p_to: args.to } : {}),
        ...(args.ids ? { p_ids: [...args.ids] } : {}),
      }),
    )
    if (typeof csv !== 'string') throw new AppError('export_transactions_csv returned no file')
    return csv
  }

  async updateCategory(id: string, edit: CategoryEdit) {
    const row = await run(
      this.client
        .from('categories')
        .update({ name: edit.name.trim(), icon: edit.icon, color: edit.color })
        .eq('id', id)
        .select(CATEGORY_COLUMNS)
        .maybeSingle(),
    )
    if (!row) throw new AppError('Category not found', 'PGRST116')
    return categoryFromRow(row)
  }

  async insertCategory(name: string, kind: CategoryKind) {
    // Only name and kind: the categories_default_style trigger fills in the
    // icon and colour (the generated Insert type doesn't know about it).
    const insert = { name: name.trim(), kind } as Database['public']['Tables']['categories']['Insert']
    const row = await run(this.client.from('categories').insert(insert).select(CATEGORY_COLUMNS).maybeSingle())
    if (!row) throw new AppError('insertCategory returned no row')
    return categoryFromRow(row)
  }

  async setCategoryArchived(id: string, archived: boolean) {
    await run(this.client.from('categories').update({ archived }).eq('id', id).select('id').single())
  }

  async fetchMonthlyTotals(from: YearMonth, to: YearMonth) {
    const rows = await run(this.client.rpc('get_monthly_totals', { p_from_month: monthStart(from), p_to_month: monthStart(to) }))
    return rows.map(monthlyTotalFromRow)
  }

  async fetchMonthlyCategoryTotals(from: YearMonth, to: YearMonth) {
    const rows = await run(
      this.client.rpc('get_monthly_category_totals', { p_from_month: monthStart(from), p_to_month: monthStart(to) }),
    )
    return rows.map(monthlyCategoryTotalFromRow)
  }

  async fetchAccountTotals(month: YearMonth) {
    const rows = await run(this.client.rpc('get_account_totals', { p_month: monthStart(month) }))
    return rows.map(accountTotalsFromRow)
  }

  async fetchProfile(userId: string) {
    const row = await run(this.client.from('profiles').select('*').eq('id', userId).maybeSingle())
    if (!row) throw new AppError('Profile not found', 'PGRST116')
    return profileFromRow(row)
  }

  async updateProfileTheme(userId: string, theme: string) {
    await run(this.client.from('profiles').update({ theme }).eq('id', userId).select('id').single())
  }

  async fetchBills() {
    const rows = await run(this.client.rpc('get_bill_schedule', {}))
    return rows.map(billFromRow)
  }

  async insertBill(id: string, draft: BillDraft) {
    try {
      // paid_through_month is filled in by the database (the first month still owed).
      const row = { id, ...billDraftToRow(draft) } as Database['public']['Tables']['recurring_bills']['Insert']
      await run(this.client.from('recurring_bills').insert(row))
    } catch (e) {
      // An earlier attempt with this id already went through.
      if (e instanceof AppError && e.code === '23505' && /pkey/.test(e.message)) return
      throw e
    }
  }

  async updateBill(id: string, draft: BillDraft) {
    await run(this.client.from('recurring_bills').update(billDraftToRow(draft)).eq('id', id).select('id').single())
  }

  async setBillReminder(id: string, enabled: boolean) {
    await run(this.client.from('recurring_bills').update({ reminder_enabled: enabled }).eq('id', id).select('id').single())
  }

  async deleteBill(id: string) {
    await run(this.client.from('recurring_bills').delete().eq('id', id))
  }

  async markBillPaid(args: {
    billId: string
    month: YearMonth
    txnId: string | null
    amountPaise?: number
    paidOn?: string
    paymentMethod?: PaymentMethod | null
  }) {
    const rows = await run(
      this.client.rpc('mark_bill_paid', {
        p_bill_id: args.billId,
        p_month: monthStart(args.month),
        ...(args.txnId ? { p_txn_id: args.txnId } : {}),
        ...(args.amountPaise !== undefined ? { p_amount_paise: args.amountPaise } : {}),
        ...(args.paidOn ? { p_paid_on: args.paidOn } : {}),
        ...(args.paymentMethod ? { p_payment_method: args.paymentMethod } : {}),
      }),
    )
    const r = rows[0]
    if (!r) throw new AppError('mark_bill_paid returned no row')
    return {
      paidThroughMonth: monthOfRow(r.paid_through_month),
      transactionId: (r.transaction_id as string | null) ?? null,
      alreadyPaid: r.already_paid,
    }
  }

  async setBillPaidThrough(id: string, month: YearMonth) {
    await run(
      this.client.from('recurring_bills').update({ paid_through_month: monthStart(month) }).eq('id', id).select('id').single(),
    )
  }

  watchChanges(userId: string, onChange: (c: DataChange) => void, onStatus: (s: LiveStatus) => void) {
    onStatus('connecting')
    let channel: RealtimeChannel | null = this.client.channel(`ventrafin-sync-${userId}`)
    for (const table of REALTIME_TABLES) {
      channel = channel.on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table,
          // RLS already limits events to the user's own rows; the filter just
          // saves the server some work.
          filter: `${table === 'profiles' ? 'id' : 'owner_id'}=eq.${userId}`,
        },
        () => onChange({ table }),
      )
    }
    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        onStatus('live')
        // (Re)connected: anything that changed while the channel was down
        // was missed, so everything on screen should re-fetch.
        onChange({ resync: true })
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        onStatus('reconnecting')
      }
    })
    return () => {
      const ch = channel
      channel = null
      if (ch) void this.client.removeChannel(ch)
    }
  }
}
