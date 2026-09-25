import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/models.dart';

/// What the Transactions list narrows to, on top of the month (or the
/// search): a type and/or a category, where "Uncategorized" is a choice too.
@immutable
class TxnFilter {
  const TxnFilter({this.type, this.categoryId, this.uncategorized = false})
      : assert(categoryId == null || !uncategorized);

  /// Only the Uncategorized entries (Dashboard card, the summary's count).
  const TxnFilter.uncategorized() : this(uncategorized: true);

  /// Null = every type.
  final TxnType? type;

  /// One category; null = every category.
  final String? categoryId;

  /// Only expenses and income without a category.
  final bool uncategorized;

  bool get isActive => type != null || hasCategory;
  bool get hasCategory => categoryId != null || uncategorized;

  TxnFilter withType(TxnType? type) => TxnFilter(type: type, categoryId: categoryId, uncategorized: uncategorized);

  /// A category ([categoryId]), Uncategorized, or (both unset) every category.
  TxnFilter withCategory({String? categoryId, bool uncategorized = false}) =>
      TxnFilter(type: type, categoryId: categoryId, uncategorized: uncategorized);

  bool matches(Txn t) {
    if (type != null && t.type != type) return false;
    if (uncategorized && (t.type == TxnType.transfer || t.categoryId != null)) return false;
    if (categoryId != null && t.categoryId != categoryId) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is TxnFilter &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.uncategorized == uncategorized;

  @override
  int get hashCode => Object.hash(type, categoryId, uncategorized);
}

class TxnFilterNotifier extends Notifier<TxnFilter> {
  @override
  TxnFilter build() => const TxnFilter();

  void set(TxnFilter filter) => state = filter;

  void clear() => state = const TxnFilter();
}

final txnFilterProvider = NotifierProvider<TxnFilterNotifier, TxnFilter>(TxnFilterNotifier.new);

/// How the Transactions list is ordered. The date orders keep the day
/// groups; the amount orders are one flat list, each row showing its date.
enum TxnSort {
  newest('Newest first'),
  oldest('Oldest first'),
  largest('Largest amount first'),
  smallest('Smallest amount first');

  const TxnSort(this.label);
  final String label;

  bool get byAmount => this == largest || this == smallest;
}

class TxnSortNotifier extends Notifier<TxnSort> {
  @override
  TxnSort build() => TxnSort.newest;

  void set(TxnSort sort) => state = sort;
}

/// Kept while switching months and searching, like the filter.
final txnSortProvider = NotifierProvider<TxnSortNotifier, TxnSort>(TxnSortNotifier.new);

/// [txns] in [sort] order. Ties: the newer entry first (by date, then when
/// it was added), so equal amounts read like the normal list.
List<Txn> sortTxns(Iterable<Txn> txns, TxnSort sort) {
  int newer(Txn a, Txn b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    final byAdded = b.createdAt.compareTo(a.createdAt);
    return byAdded != 0 ? byAdded : a.id.compareTo(b.id);
  }

  return txns.toList()
    ..sort(switch (sort) {
      TxnSort.newest => newer,
      TxnSort.oldest => (a, b) => newer(b, a),
      TxnSort.largest => (a, b) {
          final c = b.amountPaise.compareTo(a.amountPaise);
          return c != 0 ? c : newer(a, b);
        },
      TxnSort.smallest => (a, b) {
          final c = a.amountPaise.compareTo(b.amountPaise);
          return c != 0 ? c : newer(a, b);
        },
    });
}

/// The Transactions search: null while closed (the month view), otherwise
/// the text typed so far. A non-blank text searches every month.
class TxnSearchNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void open() => state ??= '';

  void setText(String text) => state = text;

  void close() => state = null;
}

final txnSearchProvider = NotifierProvider<TxnSearchNotifier, String?>(TxnSearchNotifier.new);

/// Whether [t] matches the search [query]: its description, category name
/// ("Uncategorized" and "Transfer" included), account or destination
/// account name contain it (ignoring case), or the query is an amount equal
/// to it ("450", "1,250.50", "₹ 99").
bool txnMatchesSearch(
  Txn t,
  String query, {
  required Map<String, Account> accounts,
  required Map<String, Category> categories,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  bool has(String? text) => text != null && text.toLowerCase().contains(q);

  final categoryName = switch (t) {
    Txn(type: TxnType.transfer) => 'Transfer',
    Txn(categoryId: null) => 'Uncategorized',
    _ => categories[t.categoryId]?.name,
  };
  if (has(t.description) || has(categoryName)) return true;
  if (has(accounts[t.accountId]?.name)) return true;
  if (t.toAccountId != null && has(accounts[t.toAccountId]?.name)) return true;

  final paise = parseRupeesToPaise(q);
  return paise != null && paise > 0 && paise == t.amountPaise;
}
