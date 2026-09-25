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

// ---------------------------------------------------------------------------
// Reports over a range of months
// ---------------------------------------------------------------------------

/// One row of `get_monthly_totals()`: a month's totals (zero when empty).
@immutable
class MonthlyTotal {
  const MonthlyTotal({
    required this.month,
    required this.expensePaise,
    required this.incomePaise,
    required this.expenseCount,
    required this.incomeCount,
    required this.uncategorizedCount,
  });

  factory MonthlyTotal.fromRow(Map<String, dynamic> r) => MonthlyTotal(
    month: YearMonth.of(parseIsoDate(r['month'] as String)),
    expensePaise: (r['expense_paise'] as num).toInt(),
    incomePaise: (r['income_paise'] as num).toInt(),
    expenseCount: (r['expense_count'] as num).toInt(),
    incomeCount: (r['income_count'] as num).toInt(),
    uncategorizedCount: (r['uncategorized_count'] as num).toInt(),
  );

  final YearMonth month;
  final int expensePaise;
  final int incomePaise;
  final int expenseCount;
  final int incomeCount;
  final int uncategorizedCount;

  int get netPaise => incomePaise - expensePaise;

  /// Share of income not spent, in whole percent; null without income.
  int? get savedPercent => incomePaise > 0 ? (netPaise * 100 / incomePaise).round() : null;
}

/// One row of `get_monthly_category_totals()`. `categoryId == null` is
/// Uncategorized. Months with nothing in a category have no row.
@immutable
class MonthlyCategoryTotal {
  const MonthlyCategoryTotal({
    required this.month,
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.count,
    required this.totalPaise,
  });

  factory MonthlyCategoryTotal.fromRow(Map<String, dynamic> r) => MonthlyCategoryTotal(
    month: YearMonth.of(parseIsoDate(r['month'] as String)),
    kind: TxnType.fromDb(r['kind'] as String),
    categoryId: r['category_id'] as String?,
    categoryName: r['category_name'] as String,
    color: parseHexColor(r['category_color'] as String?),
    count: (r['transaction_count'] as num).toInt(),
    totalPaise: (r['total_paise'] as num).toInt(),
  );

  final YearMonth month;
  final TxnType kind;
  final String? categoryId;
  final String categoryName;
  final Color color;
  final int count;
  final int totalPaise;
}

// ---------------------------------------------------------------------------
// Profile (per-user settings)
// ---------------------------------------------------------------------------

/// `public.profiles`: theme and reminder settings, shared with the web app.
@immutable
class Profile {
  const Profile({
    required this.theme,
    required this.dailyReminderEnabled,
    required this.dailyReminderTime,
    required this.billRemindersEnabled,
    required this.billReminderDaysBefore,
  });

  factory Profile.fromRow(Map<String, dynamic> r) => Profile(
    theme: r['theme'] as String? ?? 'ocean',
    dailyReminderEnabled: r['daily_reminder_enabled'] as bool? ?? true,
    dailyReminderTime: parseDbTime(r['daily_reminder_time'] as String?) ?? kDefaultDailyReminderTime,
    billRemindersEnabled: r['bill_reminders_enabled'] as bool? ?? true,
    billReminderDaysBefore: (r['bill_reminder_days_before'] as num?)?.toInt() ?? kDefaultBillReminderDaysBefore,
  );

  /// A `profiles.theme` id (see core/theme_tokens.dart).
  final String theme;

  /// "Log today's expenses", every day at [dailyReminderTime] (India time).
  final bool dailyReminderEnabled;
  final TimeOfDay dailyReminderTime;

  /// Master switch for every bill reminder (the per-bill switches still apply).
  final bool billRemindersEnabled;

  /// Bill reminders fire this many days before the due date, and on the day.
  final int billReminderDaysBefore;
}

/// Defaults, as in the database.
const TimeOfDay kDefaultDailyReminderTime = TimeOfDay(hour: 20, minute: 30);
const int kDefaultBillReminderDaysBefore = 3;
const int kMaxBillReminderDaysBefore = 10;

/// Columns of `profiles` to change; null = leave as is.
@immutable
class ProfilePatch {
  const ProfilePatch({
    this.theme,
    this.dailyReminderEnabled,
    this.dailyReminderTime,
    this.billRemindersEnabled,
    this.billReminderDaysBefore,
  });

  final String? theme;
  final bool? dailyReminderEnabled;
  final TimeOfDay? dailyReminderTime;
  final bool? billRemindersEnabled;
  final int? billReminderDaysBefore;

  Map<String, dynamic> toRow() => {
    if (theme != null) 'theme': theme,
    if (dailyReminderEnabled != null) 'daily_reminder_enabled': dailyReminderEnabled,
    if (dailyReminderTime != null) 'daily_reminder_time': toDbTime(dailyReminderTime!),
    if (billRemindersEnabled != null) 'bill_reminders_enabled': billRemindersEnabled,
    if (billReminderDaysBefore != null) 'bill_reminder_days_before': billReminderDaysBefore,
  };

  Profile applyTo(Profile p) => Profile(
    theme: theme ?? p.theme,
    dailyReminderEnabled: dailyReminderEnabled ?? p.dailyReminderEnabled,
    dailyReminderTime: dailyReminderTime ?? p.dailyReminderTime,
    billRemindersEnabled: billRemindersEnabled ?? p.billRemindersEnabled,
    billReminderDaysBefore: billReminderDaysBefore ?? p.billReminderDaysBefore,
  );
}

/// Postgres `time` (`20:30:00`) to a [TimeOfDay].
TimeOfDay? parseDbTime(String? s) {
  final m = s == null ? null : RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  return h < 24 && min < 60 ? TimeOfDay(hour: h, minute: min) : null;
}

String toDbTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `8:30 pm`
String formatTimeOfDay(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'am' : 'pm'}';
}

// ---------------------------------------------------------------------------
// Recurring bills
// ---------------------------------------------------------------------------

/// `recurring_bills.kind`
enum BillKind {
  utility('utility', 'Utility bill'),
  emi('emi', 'Loan EMI');

  const BillKind(this.db, this.label);
  final String db;
  final String label;

  static BillKind fromDb(String v) => values.firstWhere((k) => k.db == v, orElse: () => utility);
}

/// `get_bill_schedule().status`
enum BillStatus {
  overdue('overdue'),
  dueToday('due_today'),
  dueSoon('due_soon'),
  upcoming('upcoming');

  const BillStatus(this.db);
  final String db;

  static BillStatus fromDb(String v) => values.firstWhere((s) => s.db == v, orElse: () => upcoming);
}

/// A recurring bill with its next unpaid due date, from `get_bill_schedule()`.
/// Due dates and status are computed in Postgres, the same for both apps.
@immutable
class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.kind,
    required this.amountPaise,
    required this.dueDay,
    required this.accountId,
    required this.categoryId,
    required this.reminderEnabled,
    required this.paidThroughMonth,
    required this.nextDueDate,
    required this.daysUntil,
    required this.status,
    required this.overdueCount,
  });

  factory Bill.fromScheduleRow(Map<String, dynamic> r) => Bill(
    id: r['id'] as String,
    name: r['name'] as String,
    kind: BillKind.fromDb(r['kind'] as String),
    amountPaise: (r['amount_paise'] as num).toInt(),
    dueDay: (r['due_day'] as num).toInt(),
    accountId: r['account_id'] as String,
    categoryId: r['category_id'] as String?,
    reminderEnabled: r['reminder_enabled'] as bool? ?? true,
    paidThroughMonth: YearMonth.of(parseIsoDate(r['paid_through_month'] as String)),
    nextDueDate: parseIsoDate(r['next_due_date'] as String),
    daysUntil: (r['days_until'] as num).toInt(),
    status: BillStatus.fromDb(r['status'] as String),
    overdueCount: (r['overdue_count'] as num).toInt(),
  );

  final String id;
  final String name;
  final BillKind kind;
  final int amountPaise;

  /// 1–31; months without that day use their last day.
  final int dueDay;
  final String accountId;
  final String? categoryId;
  final bool reminderEnabled;

  /// The latest month whose bill is settled.
  final YearMonth paidThroughMonth;

  /// Due date of the first unpaid month.
  final DateTime nextDueDate;

  /// Days from today to [nextDueDate]; negative when overdue.
  final int daysUntil;
  final BillStatus status;

  /// Unpaid months whose due date has passed.
  final int overdueCount;

  /// The month whose bill is due next (what "Mark paid" settles).
  YearMonth get nextDueMonth => YearMonth.of(nextDueDate);

  BillDraft toDraft() => BillDraft(
    name: name,
    kind: kind,
    amountPaise: amountPaise,
    dueDay: dueDay,
    accountId: accountId,
    categoryId: categoryId,
    reminderEnabled: reminderEnabled,
  );
}

/// What the bill form writes.
@immutable
class BillDraft {
  const BillDraft({
    required this.name,
    required this.kind,
    required this.amountPaise,
    required this.dueDay,
    required this.accountId,
    this.categoryId,
    this.reminderEnabled = true,
  });

  final String name;
  final BillKind kind;
  final int amountPaise;
  final int dueDay;
  final String accountId;
  final String? categoryId;
  final bool reminderEnabled;

  /// owner_id defaults to auth.uid(); paid_through_month is filled in by the
  /// database on insert (the first bill still owed).
  Map<String, dynamic> toRow() => {
    'name': name.trim(),
    'kind': kind.db,
    'amount_paise': amountPaise,
    'due_day': dueDay,
    'account_id': accountId,
    'category_id': categoryId,
    'reminder_enabled': reminderEnabled,
  };
}

/// Longest bill name the database accepts (`recurring_bills_name_check`).
const int kBillNameMaxLength = 60;

/// Due date of a bill in [month]: [dueDay] clamped to the month's last day.
/// Same rule as `private.bill_due_date` in the database; the phone needs it
/// to schedule reminders for the months after the next one.
DateTime billDueDate(YearMonth month, int dueDay) {
  final last = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, dueDay < last ? dueDay : last);
}

/// `10th of every month`; 31 reads as the last day.
String dueDayLabel(int day) {
  if (day >= 31) return 'last day of every month';
  final suffix = (day >= 11 && day <= 13)
      ? 'th'
      : switch (day % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$day$suffix of every month';
}

/// What `mark_bill_paid()` did.
@immutable
class MarkPaidResult {
  const MarkPaidResult({required this.paidThroughMonth, required this.transactionId, required this.alreadyPaid});

  factory MarkPaidResult.fromRow(Map<String, dynamic> r) => MarkPaidResult(
    paidThroughMonth: YearMonth.of(parseIsoDate(r['paid_through_month'] as String)),
    transactionId: r['transaction_id'] as String?,
    alreadyPaid: r['already_paid'] as bool? ?? false,
  );

  final YearMonth paidThroughMonth;

  /// The logged expense, if one was asked for and exists.
  final String? transactionId;

  /// The month was already paid (on the other app, or by an earlier retry).
  final bool alreadyPaid;
}
