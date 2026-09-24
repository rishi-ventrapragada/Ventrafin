import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../core/india_time.dart';
import 'entry_prefs.dart';
import 'models.dart';
import 'repository.dart';
import 'supabase_repository.dart';

// ---------------------------------------------------------------------------
// Composition root. main.dart overrides the "must be overridden" providers;
// tests override the repository, prefs, connectivity and clock.
// ---------------------------------------------------------------------------

final appConfigProvider = Provider<AppConfig>((ref) => throw UnimplementedError('override in main'));

final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repositoryProvider =
    Provider<FinanceRepository>((ref) => SupabaseFinanceRepository(ref.watch(supabaseClientProvider)));

final entryPrefsProvider = Provider<EntryPrefs>((ref) => EntryPrefs(ref.watch(sharedPreferencesProvider)));

/// Clock seam: "today" is always computed in India time from this.
final clockProvider = Provider<Clock>((ref) => systemClock);

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// The current Supabase session, kept in sync with auth events. Synchronous,
/// so the router can decide redirects without waiting.
class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() {
    final client = ref.watch(supabaseClientProvider);
    final sub = client.auth.onAuthStateChange.listen((data) => state = data.session);
    ref.onDispose(sub.cancel);
    return client.auth.currentSession;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

final currentUserProvider = Provider<User?>((ref) => ref.watch(sessionProvider)?.user);

/// Only changes when a different user signs in or out (not on token refresh).
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(currentUserProvider)?.id);

// ---------------------------------------------------------------------------
// Connectivity
// ---------------------------------------------------------------------------

/// Whether the phone has any network. It can't prove the internet works
/// (captive Wi-Fi etc.), so request errors are still reported individually.
final onlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);
  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});

/// True unless we positively know we're offline.
final isOnlineProvider = Provider<bool>((ref) => ref.watch(onlineProvider).value ?? true);

// ---------------------------------------------------------------------------
// Realtime -> revisions
// ---------------------------------------------------------------------------

/// A counter per table, bumped whenever Realtime reports a change. Data
/// providers watch their table's counter, so they re-fetch automatically.
class Revisions extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void bump(Iterable<String> tables) {
    final next = Map<String, int>.of(state);
    for (final t in tables) {
      next[t] = (next[t] ?? 0) + 1;
    }
    state = next;
  }

  void bumpAll() => bump(kRealtimeTables);
}

final revisionsProvider = NotifierProvider<Revisions, Map<String, int>>(Revisions.new);

int _revision(Ref ref, String table) => ref.watch(revisionsProvider.select((r) => r[table] ?? 0));

/// Coalesces bursts (e.g. many rows pasted on the web app) into one re-fetch.
const Duration kRealtimeDebounce = Duration(milliseconds: 300);

/// Keeps the Realtime subscription open while the signed-in app shell is on
/// screen, and turns change events into revision bumps.
final realtimeSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return;
  final repo = ref.watch(repositoryProvider);
  final revisions = ref.read(revisionsProvider.notifier);

  final pending = <String>{};
  Timer? timer;

  final sub = repo.watchChanges().listen((change) {
    if (change.resync) {
      // (Re)connected: anything that changed while the channel was down (or
      // between the first load and the subscription going live) was missed,
      // so re-fetch everything on screen.
      revisions.bumpAll();
      return;
    }
    pending.add(change.table!);
    timer?.cancel();
    timer = Timer(kRealtimeDebounce, () {
      revisions.bump(pending.toList());
      pending.clear();
    });
  });

  ref.onDispose(() {
    timer?.cancel();
    sub.cancel();
  });
});

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

final accountsProvider = FutureProvider<List<Account>>((ref) {
  _revision(ref, 'accounts');
  ref.watch(currentUserIdProvider);
  return ref.watch(repositoryProvider).fetchAccounts();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  _revision(ref, 'categories');
  ref.watch(currentUserIdProvider);
  return ref.watch(repositoryProvider).fetchCategories();
});

final monthTransactionsProvider = FutureProvider.autoDispose.family<List<Txn>, YearMonth>((ref, month) {
  _revision(ref, 'transactions');
  ref.watch(currentUserIdProvider);
  return ref.watch(repositoryProvider).fetchTransactions(month);
});

final monthTotalsProvider = FutureProvider.autoDispose.family<MonthTotals, YearMonth>((ref, month) {
  _revision(ref, 'transactions');
  ref.watch(currentUserIdProvider);
  return ref.watch(repositoryProvider).fetchMonthTotals(month);
});

final transactionProvider = FutureProvider.autoDispose.family<Txn?, String>((ref, id) {
  _revision(ref, 'transactions');
  return ref.watch(repositoryProvider).fetchTransaction(id);
});

/// Month shown on the Transactions screen (defaults to the current month in India).
class SelectedMonth extends Notifier<YearMonth> {
  @override
  YearMonth build() => YearMonth.of(indiaToday(ref.watch(clockProvider)));

  void set(YearMonth month) => state = month;
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, YearMonth>(SelectedMonth.new);

/// Ids deleted on this device, hidden immediately so a swiped-away row
/// doesn't linger (or reappear) until the re-fetch arrives.
class HiddenTxnIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void hide(String id) => state = {...state, id};
}

final hiddenTxnIdsProvider = NotifierProvider<HiddenTxnIds, Set<String>>(HiddenTxnIds.new);
