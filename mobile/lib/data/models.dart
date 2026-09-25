import 'package:flutter/material.dart';

import '../core/india_time.dart';

/// `transactions.type`
enum TxnType {
  expense('expense', 'Expense'),
  income('income', 'Income'),
  transfer('transfer', 'Transfer');

  const TxnType(this.db, this.label);
  final String db;
  final String label;

  static TxnType fromDb(String v) => values.firstWhere((t) => t.db == v);
}

/// `transactions.payment_method`
enum PaymentMethod {
  cash('cash', 'Cash'),
  upi('upi', 'UPI'),
  debit('debit', 'Debit'),
  card('card', 'Card');

  const PaymentMethod(this.db, this.label);
  final String db;
  final String label;

  static PaymentMethod? fromDb(String? v) =>
      v == null ? null : values.where((m) => m.db == v).firstOrNull;
}

/// `accounts.type`
enum AccountType {
  cash('cash', 'Cash'),
  bank('bank', 'Bank'),
  credit('credit', 'Credit card');

  const AccountType(this.db, this.label);
  final String db;
  final String label;

  static AccountType fromDb(String v) => values.firstWhere((t) => t.db == v, orElse: () => cash);
}

@immutable
class Account {
  const Account({required this.id, required this.name, required this.type});

  factory Account.fromRow(Map<String, dynamic> r) => Account(
        id: r['id'] as String,
        name: r['name'] as String,
        type: AccountType.fromDb(r['type'] as String),
      );

  final String id;
  final String name;
  final AccountType type;
}

@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    required this.archived,
    this.iconKey = 'label',
  });

  factory Category.fromRow(Map<String, dynamic> r) => Category(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: TxnType.fromDb(r['kind'] as String),
        color: parseHexColor(r['color'] as String?),
        archived: r['archived'] as bool? ?? false,
        iconKey: r['icon'] as String? ?? 'label',
      );

  final String id;
  final String name;

  /// [TxnType.expense] or [TxnType.income].
  final TxnType kind;
  final Color color;
  final bool archived;

  /// Key from the curated icon set (`categories.icon`), see core/category_style.dart.
  final String iconKey;
}

/// Longest category name the database accepts (`categories_name_check`).
const int kCategoryNameMaxLength = 40;

/// Why [name] can't be used for a category of [kind], or null if it can.
/// Mirrors the database's rules so the form can say so before saving:
/// 1–40 characters, "Uncategorized" is reserved, and names are unique per
/// kind ignoring case (archived categories count too). The database still
/// enforces all of them.
String? categoryNameError(
  String name, {
  required TxnType kind,
  required Iterable<Category> existing,
  String? exceptId,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Enter a name';
  if (trimmed.runes.length > kCategoryNameMaxLength) {
    return 'Keep it to $kCategoryNameMaxLength characters or fewer';
  }
  final lower = trimmed.toLowerCase();
  if (lower == 'uncategorized') return '"Uncategorized" is reserved for entries without a category';
  final clash = existing
      .where((c) => c.id != exceptId && c.kind == kind && c.name.trim().toLowerCase() == lower)
      .firstOrNull;
  if (clash != null) {
    final article = kind == TxnType.income ? 'an income' : 'an expense';
    return 'You already have $article category called "${clash.name}"${clash.archived ? ' (archived)' : ''}';
  }
  return null;
}

Color parseHexColor(String? hex, {Color fallback = const Color(0xFF9E9E9E)}) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// A row of `public.transactions`.
@immutable
class Txn {
  const Txn({
    required this.id,
    required this.date,
    required this.amountPaise,
    required this.description,
    required this.type,
    required this.accountId,
    required this.toAccountId,
    required this.categoryId,
    required this.paymentMethod,
    required this.autoCategorized,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Txn.fromRow(Map<String, dynamic> r) => Txn(
        id: r['id'] as String,
        date: parseIsoDate(r['date'] as String),
        amountPaise: (r['amount_paise'] as num).toInt(),
        description: r['description'] as String? ?? '',
        type: TxnType.fromDb(r['type'] as String),
        accountId: r['account_id'] as String,
        toAccountId: r['to_account_id'] as String?,
        categoryId: r['category_id'] as String?,
        paymentMethod: PaymentMethod.fromDb(r['payment_method'] as String?),
        autoCategorized: r['auto_categorized'] as bool? ?? false,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  final String id;
  final DateTime date;
  final int amountPaise;
  final String description;
  final TxnType type;
  final String accountId;
  final String? toAccountId;

  /// Null = Uncategorized (always null for transfers).
  final String? categoryId;
  final PaymentMethod? paymentMethod;
  final bool autoCategorized;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// What the entry form writes. `categoryId == null` means "let the database
/// auto-categorize" (ARCHITECTURE.md § 3).
@immutable
class TxnDraft {
  const TxnDraft({
    required this.date,
    required this.amountPaise,
    required this.description,
    required this.type,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.paymentMethod,
  });

  final DateTime date;
  final int amountPaise;
  final String description;
  final TxnType type;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final PaymentMethod? paymentMethod;

  /// Columns sent to Supabase. owner_id is omitted on purpose: it defaults to
  /// auth.uid() in the database and RLS verifies it.
  Map<String, dynamic> toRow() => {
        'date': toIsoDate(date),
        'amount_paise': amountPaise,
        'description': description.trim(),
        'type': type.db,
        'account_id': accountId,
        'to_account_id': type == TxnType.transfer ? toAccountId : null,
        'category_id': type == TxnType.transfer ? null : categoryId,
        'payment_method': paymentMethod?.db,
      };
}

/// One row of `get_month_totals()`.
@immutable
class MonthTotals {
  const MonthTotals({
    required this.expensePaise,
    required this.lastExpensePaise,
    required this.incomePaise,
    required this.lastIncomePaise,
    required this.uncategorizedCount,
  });

  factory MonthTotals.fromRow(Map<String, dynamic> r) => MonthTotals(
        expensePaise: (r['expense_paise'] as num).toInt(),
        lastExpensePaise: (r['last_expense_paise'] as num).toInt(),
        incomePaise: (r['income_paise'] as num).toInt(),
        lastIncomePaise: (r['last_income_paise'] as num).toInt(),
        uncategorizedCount: (r['uncategorized_count'] as num).toInt(),
      );

  final int expensePaise;
  final int lastExpensePaise;
  final int incomePaise;
  final int lastIncomePaise;
  final int uncategorizedCount;

  int get netPaise => incomePaise - expensePaise;
}

/// One row of `get_month_comparison()`: a category's total this month and
/// last month. `categoryId == null` is Uncategorized.
@immutable
class CategoryComparison {
  const CategoryComparison({
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.thisMonthPaise,
    required this.lastMonthPaise,
  });

  factory CategoryComparison.fromRow(Map<String, dynamic> r) => CategoryComparison(
        kind: TxnType.fromDb(r['kind'] as String),
        categoryId: r['category_id'] as String?,
        categoryName: r['category_name'] as String,
        color: parseHexColor(r['category_color'] as String?),
        thisMonthPaise: (r['this_month_paise'] as num).toInt(),
        lastMonthPaise: (r['last_month_paise'] as num).toInt(),
      );

  final TxnType kind;
  final String? categoryId;
  final String categoryName;
  final Color color;
  final int thisMonthPaise;
  final int lastMonthPaise;

  int get changePaise => thisMonthPaise - lastMonthPaise;
}
