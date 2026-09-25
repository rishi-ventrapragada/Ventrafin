import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/india_time.dart';
import 'models.dart';
import 'repository.dart';

/// Tables published to Supabase Realtime (see the realtime migrations).
const List<String> kRealtimeTables = [
  'transactions',
  'accounts',
  'categories',
  'recurring_bills',
  'profiles',
];

/// How long to wait for any single request before reporting "couldn't reach
/// the server". Without a limit a dead connection could leave a save
/// spinning forever, which would count as failing silently.
const Duration kRequestTimeout = Duration(seconds: 15);

class SupabaseFinanceRepository implements FinanceRepository {
  SupabaseFinanceRepository(this._client);

  final SupabaseClient _client;

  Future<T> _run<T>(Future<T> Function() request) => request().timeout(kRequestTimeout);

  @override
  Future<List<Account>> fetchAccounts() => _run(() async {
        final rows = await _client.from('accounts').select().order('name');
        return rows.map(Account.fromRow).toList();
      });

  @override
  Future<List<Category>> fetchCategories() => _run(() async {
        final rows = await _client.from('categories').select().order('name');
        return rows.map(Category.fromRow).toList();
      });

  @override
  Future<List<Txn>> fetchTransactions(YearMonth month) => _run(() async {
        final rows = await _client
            .from('transactions')
            .select()
            .gte('date', toIsoDate(month.firstDay))
            .lt('date', toIsoDate(month.next.firstDay))
            .order('date', ascending: false)
            .order('created_at', ascending: false);
        return rows.map(Txn.fromRow).toList();
      });

  @override
  Future<Txn?> fetchTransaction(String id) => _run(() async {
        final row = await _client.from('transactions').select().eq('id', id).maybeSingle();
        return row == null ? null : Txn.fromRow(row);
      });

  @override
  Future<MonthTotals> fetchMonthTotals(YearMonth month) => _run(() async {
        final rows = await _client.rpc<List<dynamic>>(
          'get_month_totals',
          params: {'p_month': toIsoDate(month.firstDay)},
        );
        return MonthTotals.fromRow(rows.first as Map<String, dynamic>);
      });

  @override
  Future<List<CategoryComparison>> fetchMonthComparison(YearMonth month) => _run(() async {
        final rows = await _client.rpc<List<dynamic>>(
          'get_month_comparison',
          params: {'p_month': toIsoDate(month.firstDay)},
        );
        return rows.map((r) => CategoryComparison.fromRow(r as Map<String, dynamic>)).toList();
      });

  @override
  Future<Category> updateCategory(String id, {required String name, required String iconKey, required String colorHex}) =>
      _run(() async {
        final row = await _client
            .from('categories')
            .update({'name': name.trim(), 'icon': iconKey, 'color': colorHex})
            .eq('id', id)
            .select()
            .single();
        return Category.fromRow(row);
      });

  @override
  Future<Txn> insertTransaction(String id, TxnDraft draft) async {
    try {
      return await _run(() async {
        final row = await _client
            .from('transactions')
            .insert({'id': id, ...draft.toRow()})
            .select()
            .single();
        return Txn.fromRow(row);
      });
    } on PostgrestException catch (e) {
      // 23505 on the primary key: an earlier attempt with this id already
      // succeeded (its response was lost). Treat it as saved.
      if (e.code == '23505') {
        final existing = await fetchTransaction(id);
        if (existing != null) return existing;
      }
      rethrow;
    }
  }

  @override
  Future<Txn> updateTransaction(String id, TxnDraft draft) => _run(() async {
        final row = await _client.from('transactions').update(draft.toRow()).eq('id', id).select().single();
        return Txn.fromRow(row);
      });

  @override
  Future<String> exportTransactionsCsv({DateTime? from, DateTime? to}) => _run(() async {
        final csv = await _client.rpc<dynamic>(
          'export_transactions_csv',
          params: {
            if (from != null) 'p_from': toIsoDate(from),
            if (to != null) 'p_to': toIsoDate(to),
          },
        );
        if (csv is! String) throw const PostgrestException(message: 'export_transactions_csv returned no file');
        return csv;
      });

  @override
  Future<void> deleteTransaction(String id) => _run(() async {
        // .select() makes a no-op delete (row already gone, or not ours)
        // visible instead of silently "succeeding".
        final deleted = await _client.from('transactions').delete().eq('id', id).select('id');
        if (deleted.isEmpty) {
          throw const PostgrestException(message: 'Transaction not found', code: 'PGRST116');
        }
      });

  @override
  Future<List<MonthlyTotal>> fetchMonthlyTotals(YearMonth from, YearMonth to) => _run(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_monthly_totals',
      params: {'p_from_month': toIsoDate(from.firstDay), 'p_to_month': toIsoDate(to.firstDay)},
    );
    return rows.map((r) => MonthlyTotal.fromRow(r as Map<String, dynamic>)).toList();
  });

  @override
  Future<List<MonthlyCategoryTotal>> fetchMonthlyCategoryTotals(YearMonth from, YearMonth to) => _run(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_monthly_category_totals',
      params: {'p_from_month': toIsoDate(from.firstDay), 'p_to_month': toIsoDate(to.firstDay)},
    );
    return rows.map((r) => MonthlyCategoryTotal.fromRow(r as Map<String, dynamic>)).toList();
  });

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Not signed in');
    return id;
  }

  @override
  Future<Profile> fetchProfile() => _run(() async {
    final row = await _client.from('profiles').select().eq('id', _userId).single();
    return Profile.fromRow(row);
  });

  @override
  Future<void> updateProfile(ProfilePatch patch) => _run(() async {
    final row = patch.toRow();
    if (row.isEmpty) return;
    await _client.from('profiles').update(row).eq('id', _userId).select('id').single();
  });

  @override
  Future<List<Bill>> fetchBills() => _run(() async {
    final rows = await _client.rpc<List<dynamic>>('get_bill_schedule');
    return rows.map((r) => Bill.fromScheduleRow(r as Map<String, dynamic>)).toList();
  });

  @override
  Future<void> insertBill(String id, BillDraft draft) async {
    try {
      await _run(() => _client.from('recurring_bills').insert({'id': id, ...draft.toRow()}));
    } on PostgrestException catch (e) {
      // An earlier attempt with this id already went through.
      if (e.code == '23505' && e.message.contains('pkey')) return;
      rethrow;
    }
  }

  @override
  Future<void> updateBill(String id, BillDraft draft) => _run(() async {
    await _client.from('recurring_bills').update(draft.toRow()).eq('id', id).select('id').single();
  });

  @override
  Future<void> setBillReminder(String id, bool enabled) => _run(() async {
    await _client.from('recurring_bills').update({'reminder_enabled': enabled}).eq('id', id).select('id').single();
  });

  @override
  Future<void> deleteBill(String id) => _run(() async {
    await _client.from('recurring_bills').delete().eq('id', id);
  });

  @override
  Future<MarkPaidResult> markBillPaid({
    required String billId,
    required YearMonth month,
    String? txnId,
    int? amountPaise,
    DateTime? paidOn,
    PaymentMethod? paymentMethod,
  }) => _run(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'mark_bill_paid',
      params: {
        'p_bill_id': billId,
        'p_month': toIsoDate(month.firstDay),
        'p_txn_id': txnId,
        'p_amount_paise': amountPaise,
        'p_paid_on': paidOn == null ? null : toIsoDate(paidOn),
        'p_payment_method': paymentMethod?.db,
      },
    );
    return MarkPaidResult.fromRow(rows.first as Map<String, dynamic>);
  });

  @override
  Future<void> setBillPaidThrough(String id, YearMonth month) => _run(() async {
    await _client
        .from('recurring_bills')
        .update({'paid_through_month': toIsoDate(month.firstDay)})
        .eq('id', id)
        .select('id')
        .single();
  });

  @override
  Stream<DataChange> watchChanges() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();

    late final StreamController<DataChange> controller;
    RealtimeChannel? channel;

    controller = StreamController<DataChange>(
      onListen: () {
        var ch = _client.channel('ventrafin-sync-$userId');
        for (final table in kRealtimeTables) {
          ch = ch.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            // RLS already limits events to the user's own rows; the filter
            // just saves the server some work.
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: table == 'profiles' ? 'id' : 'owner_id',
              value: userId,
            ),
            callback: (_) {
              if (!controller.isClosed) controller.add(DataChange.table(table));
            },
          );
        }
        channel = ch.subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed && !controller.isClosed) {
            controller.add(const DataChange.resync());
          }
        });
      },
      onCancel: () async {
        final ch = channel;
        channel = null;
        if (ch != null) await _client.removeChannel(ch);
      },
    );
    return controller.stream;
  }
}
