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
  });

  factory Category.fromRow(Map<String, dynamic> r) => Category(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: TxnType.fromDb(r['kind'] as String),
        color: parseHexColor(r['color'] as String?),
        archived: r['archived'] as bool? ?? false,
      );

  final String id;
  final String name;

  /// [TxnType.expense] or [TxnType.income].
  final TxnType kind;
  final Color color;
  final bool archived;
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
