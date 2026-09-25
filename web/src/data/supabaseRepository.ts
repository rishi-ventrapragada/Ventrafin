import type { RealtimeChannel } from '@supabase/supabase-js'
import { monthStart, nextMonth, type YearMonth } from '@/lib/dates'
import { AppError, toAppError } from '@/lib/errors'
import {
  accountFromRow,
  categoryFromRow,
  comparisonFromRow,
  draftToRow,
  monthTotalsFromRow,
  patchToRow,
  txnFromRow,
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

export class SupabaseFinanceRepository implements FinanceRepository {
  constructor(private readonly client: AppSupabaseClient) {}

  async fetchAccounts() {
    const rows = await run(this.client.from('accounts').select('id, name, type').order('name'))
    return rows.map(accountFromRow)
  }

  async fetchCategories() {
    const rows = await run(this.client.from('categories').select('id, name, kind, color, archived, icon').order('name'))
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

  async updateCategory(id: string, edit: CategoryEdit) {
    const row = await run(
      this.client
        .from('categories')
        .update({ name: edit.name.trim(), icon: edit.icon, color: edit.color })
        .eq('id', id)
        .select('id, name, kind, color, archived, icon')
        .maybeSingle(),
    )
    if (!row) throw new AppError('Category not found', 'PGRST116')
    return categoryFromRow(row)
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
