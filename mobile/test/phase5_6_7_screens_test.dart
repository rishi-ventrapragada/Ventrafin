import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/features/bills/bill_form_screen.dart';
import 'package:ventrafin/features/bills/bills_screen.dart';
import 'package:ventrafin/features/reminders/reminder_notifications.dart';
import 'package:ventrafin/features/reminders/reminder_plan.dart';
import 'package:ventrafin/features/reminders/reminder_prompt.dart';
import 'package:ventrafin/features/reminders/reminder_sync.dart';
import 'package:ventrafin/features/reports/report_data.dart';
import 'package:ventrafin/features/reports/reports_screen.dart';
import 'package:ventrafin/features/settings/settings_screen.dart';

import 'support/fake_repository.dart';

class FakeNotifications implements ReminderNotifications {
  FakeNotifications({this.allowed = true, this.exact = true});

  bool allowed;
  bool exact;
  bool grantOnRequest = false;
  int permissionRequests = 0;
  int settingsOpened = 0;
  int exactRequests = 0;
  final scheduled = <({List<PlannedReminder> plan, bool exact})>[];

  @override
  Future<ReminderPermissions> permissions() async =>
      ReminderPermissions(notificationsAllowed: allowed, exactAlarmsAllowed: exact);

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    if (grantOnRequest) allowed = true;
    return allowed;
  }

  @override
  Future<bool> requestExactAlarms() async {
    exactRequests++;
    return exact;
  }

  @override
  Future<void> openNotificationSettings() async => settingsOpened++;

  @override
  Future<void> replaceAll(List<PlannedReminder> plan, {required bool exact}) async =>
      scheduled.add((plan: plan, exact: exact));

  @override
  Future<void> showTest() async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<String> get opened => const Stream.empty();
}

MonthlyTotal _mt(int y, int m, int spent, int income) => MonthlyTotal(
  month: YearMonth(y, m),
  expensePaise: spent,
  incomePaise: income,
  expenseCount: 3,
  incomeCount: 1,
  uncategorizedCount: 0,
);

MonthlyCategoryTotal _ct(int m, String? id, String name, int paise, {int color = 0xFFFB8C00}) => MonthlyCategoryTotal(
  month: YearMonth(2026, m),
  kind: TxnType.expense,
  categoryId: id,
  categoryName: name,
  color: Color(color),
  count: 2,
  totalPaise: paise,
);

Bill _bill({BillStatus status = BillStatus.dueSoon, int daysUntil = 3, bool reminder = true}) => Bill(
  id: 'bill-1',
  name: 'BESCOM',
  kind: BillKind.utility,
  amountPaise: 145000,
  dueDay: 28,
  accountId: 'acc-bank',
  categoryId: 'cat-elec',
  reminderEnabled: reminder,
  paidThroughMonth: const YearMonth(2026, 8),
  nextDueDate: DateTime(2026, 9, 28),
  daysUntil: daysUntil,
  status: status,
  overdueCount: status == BillStatus.overdue ? 1 : 0,
);

extension on Bill {
  Bill copyWithName(String name) => Bill(
    id: '$id-2',
    name: name,
    kind: BillKind.emi,
    amountPaise: 123456700,
    dueDay: dueDay,
    accountId: accountId,
    categoryId: null,
    reminderEnabled: false,
    paidThroughMonth: paidThroughMonth,
    nextDueDate: nextDueDate,
    daysUntil: daysUntil,
    status: status,
    overdueCount: 2,
  );
}

void main() {
  group('Reports', () {
    test('trend: top 5 categories keep their colour, the rest fold into Other', () {
      final months = monthsEnding(const YearMonth(2026, 9), 3);
      expect(months, [const YearMonth(2026, 7), const YearMonth(2026, 8), const YearMonth(2026, 9)]);
      final trend = buildCategoryTrend(
        [
          for (var i = 0; i < 7; i++) _ct(9, 'c$i', 'Cat $i', (i + 1) * 1000),
          _ct(7, null, 'Uncategorized', 500),
          _ct(3, 'c0', 'Cat 0', 99999), // outside the range
        ],
        months,
        const {},
      );
      expect(trend.rows.map((r) => r.name).take(2), ['Cat 6', 'Cat 5']);
      expect(trend.rows, hasLength(8));
      expect(trend.series, hasLength(6));
      expect(trend.series.last.name, 'Other (3)');
      expect(trend.series.last.perMonth, [500, 0, 1000 + 2000]);
      expect(trend.monthTotals.last, 28000);
      expect(trend.rows.firstWhere((r) => r.isUncategorized).perMonth, [500, 0, 0]);
    });

    testWidgets('month summary, category tables and both trends from the database functions', (tester) async {
      final repo = FakeRepository()
        ..totals = const MonthTotals(
          expensePaise: 3000000,
          lastExpensePaise: 2500000,
          incomePaise: 6000000,
          lastIncomePaise: 6000000,
          uncategorizedCount: 1,
        )
        ..comparison = [
          CategoryComparison(
            kind: TxnType.expense,
            categoryId: 'cat-food',
            categoryName: 'Food',
            color: const Color(0xFFFB8C00),
            thisMonthPaise: 2000000,
            lastMonthPaise: 1000000,
          ),
          CategoryComparison(
            kind: TxnType.expense,
            categoryId: null,
            categoryName: 'Uncategorized',
            color: const Color(0xFF9E9E9E),
            thisMonthPaise: 1000000,
            lastMonthPaise: 1500000,
          ),
          CategoryComparison(
            kind: TxnType.income,
            categoryId: 'cat-salary',
            categoryName: 'Salary',
            color: const Color(0xFF2E7D32),
            thisMonthPaise: 6000000,
            lastMonthPaise: 6000000,
          ),
        ]
        ..monthlyTotals = [for (var m = 4; m <= 9; m++) _mt(2026, m, m * 100000, 6000000)]
        ..monthlyCategoryTotals = [_ct(8, 'cat-food', 'Food', 1000000), _ct(9, 'cat-food', 'Food', 2000000)];
      await pumpWithFakes(tester, const ReportsScreen(), repo: repo);

      // The clock is 25 Sep 2026: the six months end with September.
      expect(repo.monthlyRanges.last, (const YearMonth(2026, 4), const YearMonth(2026, 9)));
      expect(find.text('September 2026'), findsWidgets);
      expect(find.text('₹30,000'), findsWidgets); // spent this month
      expect(find.text('50%'), findsOneWidget); // saved this month
      expect(find.byKey(const Key('report-expense-cat-food')), findsOneWidget);
      expect(find.byKey(const Key('report-expense-uncategorized')), findsOneWidget);
      expect(find.byKey(const Key('report-income-cat-salary')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('report-category-trend')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('report-income-vs-spending')), findsOneWidget);
      expect(find.byKey(const Key('pivot-scroll')), findsOneWidget);

      // 12 months: a new range is fetched.
      await tester.scrollUntilVisible(find.text('12 months'), -200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('12 months'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 months'));
      await tester.pumpAndSettle();
      expect(repo.monthlyRanges.last, (const YearMonth(2025, 10), const YearMonth(2026, 9)));
    });

    testWidgets('any past month: the picker moves every section', (tester) async {
      final repo = FakeRepository();
      await pumpWithFakes(tester, const ReportsScreen(), repo: repo);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsWidgets);
      expect(repo.monthlyRanges.last, (const YearMonth(2026, 3), const YearMonth(2026, 8)));
      // Can't go past the current month.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
      expect(next.onPressed, isNull);
    });
  });

  group('Bills', () {
    testWidgets('list with status; mark paid logs the payment with the chosen method', (tester) async {
      final repo = FakeRepository()..bills = [_bill()];
      await pumpWithFakes(tester, const BillsScreen(), repo: repo);
      expect(find.text('BESCOM'), findsOneWidget);
      expect(find.text('Due in 3 days'), findsOneWidget);
      expect(find.text('28th of every month · Bank', findRichText: true), findsNothing);

      await tester.tap(find.byKey(const Key('bill-bill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bill-action-paid')));
      await tester.pumpAndSettle();
      expect(find.text('Mark BESCOM paid for September 2026'), findsOneWidget);
      await tester.tap(find.text('Card'));
      await tester.enterText(find.byKey(const Key('paid-amount')), '1,512.50');
      await tester.pump();
      await tester.tap(find.byKey(const Key('paid-confirm')));
      await tester.pumpAndSettle();

      final call = repo.paidCalls.single;
      expect(call.month, const YearMonth(2026, 9));
      expect(call.txnId, isNotNull);
      expect(call.method, PaymentMethod.card);
      expect(call.amountPaise, 151250);
      expect(find.textContaining('marked paid for September 2026 and added to Transactions'), findsOneWidget);

      // Undo puts the month back and removes the logged expense.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.paidThroughSets.single.month, const YearMonth(2026, 8));
      expect(repo.deletedTxnIds.single, call.txnId);
    });

    testWidgets('mark paid without logging, from a bank account defaults to UPI', (tester) async {
      final repo = FakeRepository()..bills = [_bill()];
      await pumpWithFakes(tester, const BillsScreen(), repo: repo);
      await tester.tap(find.byKey(const Key('bill-bill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bill-action-paid')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paid-log-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paid-confirm')));
      await tester.pumpAndSettle();
      expect(repo.paidCalls.single.txnId, isNull);
    });

    testWidgets('overdue in red wording; the bell toggles the bill reminder', (tester) async {
      final repo = FakeRepository()..bills = [_bill(status: BillStatus.overdue, daysUntil: -4)];
      await pumpWithFakes(tester, const BillsScreen(), repo: repo);
      expect(find.text('Overdue · 4 days'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bill-reminder-bill-1')));
      await tester.pumpAndSettle();
      expect(repo.reminderToggles.single, (id: 'bill-1', enabled: false));
    });

    testWidgets('empty state', (tester) async {
      await pumpWithFakes(tester, const BillsScreen());
      expect(find.textContaining('No bills yet'), findsOneWidget);
    });

    testWidgets('add a bill: validated, then saved with a client id', (tester) async {
      final repo = FakeRepository();
      await pumpWithFakes(tester, const BillFormScreen(), repo: repo);
      await tester.tap(find.byKey(const Key('bill-save')));
      await tester.pumpAndSettle();
      expect(repo.billInserts, isEmpty);
      expect(find.textContaining('Enter a name'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('bill-name')), '  Home loan ');
      await tester.tap(find.text('Loan EMI'));
      await tester.enterText(find.byKey(const Key('bill-amount')), '25000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('bill-save')));
      await tester.pumpAndSettle();
      final saved = repo.billInserts.single;
      expect(saved.id, hasLength(36));
      expect(saved.draft.toRow(), {
        'name': 'Home loan',
        'kind': 'emi',
        'amount_paise': 2500000,
        'due_day': 10,
        'account_id': 'acc-bank',
        'category_id': null,
        'reminder_enabled': true,
      });
    });
  });

  group('Settings: reminders and theme', () {
    Future<(FakeRepository, FakeNotifications)> pumpSettings(WidgetTester tester, {FakeNotifications? n}) async {
      final notifications = n ?? FakeNotifications();
      final repo = FakeRepository()..bills = [_bill()];
      await pumpWithFakes(
        tester,
        const SettingsScreen(),
        repo: repo,
        surfaceSize: const Size(412, 2000),
        overrides: <Override>[
          reminderNotificationsProvider.overrideWithValue(notifications),
          currentUserProvider.overrideWithValue(null),
        ],
      );
      return (repo, notifications);
    }

    testWidgets('toggles save to the profile; daily and bill switches are separate', (tester) async {
      final (repo, _) = await pumpSettings(tester);
      expect(find.text('Every day at 8:30 pm'), findsOneWidget);
      expect(find.text('3 days before, and on the due date, at $kBillReminderTime'), findsOneWidget);
      expect(find.text('1 bill, 1 with reminders on'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bill-reminders-switch')));
      await tester.pumpAndSettle();
      expect(repo.profileUpdates.single.toRow(), {'bill_reminders_enabled': false});
      // The daily reminder is untouched by the master switch.
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('daily-reminder-switch'))).value, isTrue);

      await tester.tap(find.byKey(const Key('daily-reminder-switch')));
      await tester.pumpAndSettle();
      expect(repo.profileUpdates.last.toRow(), {'daily_reminder_enabled': false});
    });

    testWidgets('a failed save flips the switch back and says so', (tester) async {
      final (repo, _) = await pumpSettings(tester);
      repo.failNextProfileUpdateWith = TimeoutException('slow');
      await tester.tap(find.byKey(const Key('daily-reminder-switch')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('daily-reminder-switch'))).value, isTrue);
      expect(find.textContaining('Not saved.'), findsOneWidget);
    });

    testWidgets('notifications blocked: a banner asks, then falls back to Android settings', (tester) async {
      final (_, n) = await pumpSettings(tester, n: FakeNotifications(allowed: false));
      expect(find.byKey(const Key('notifications-blocked')), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byKey(const Key('notifications-blocked')), matching: find.text('Allow')),
      );
      await tester.pumpAndSettle();
      expect(n.permissionRequests, 1);
      expect(n.settingsOpened, 1, reason: 'refused (or asked twice already): open the app notification settings');
    });

    testWidgets('notifications granted from the banner: the banner goes away', (tester) async {
      final (_, n) = await pumpSettings(tester, n: FakeNotifications(allowed: false)..grantOnRequest = true);
      await tester.tap(
        find.descendant(of: find.byKey(const Key('notifications-blocked')), matching: find.text('Allow')),
      );
      await tester.pumpAndSettle();
      expect(n.settingsOpened, 0);
      expect(find.byKey(const Key('notifications-blocked')), findsNothing);
    });

    testWidgets('exact alarms refused: reminders still work, with a note and a way to allow', (tester) async {
      final (_, n) = await pumpSettings(tester, n: FakeNotifications(exact: false));
      expect(find.byKey(const Key('exact-alarms-off')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('exact-alarms-off')), matching: find.text('Allow')));
      await tester.pumpAndSettle();
      expect(n.exactRequests, 1);
    });

    testWidgets('picking a theme saves it to the profile', (tester) async {
      final (repo, _) = await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('theme-marigold')));
      await tester.pumpAndSettle();
      expect(repo.profileUpdates.single.toRow(), {'theme': 'marigold'});
    });
  });

  group('first-run reminder permission prompt', () {
    Future<FakeNotifications> pumpPrompt(WidgetTester tester, FakeNotifications n, {Map<String, Object> prefs = const {}}) async {
      await pumpWithFakes(
        tester,
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(onPressed: () => maybeAskForReminderPermission(context, ref), child: const Text('go')),
          ),
        ),
        prefs: prefs,
        overrides: <Override>[reminderNotificationsProvider.overrideWithValue(n)],
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return n;
    }

    testWidgets('explains first, then asks Android; only once per install', (tester) async {
      final n = await pumpPrompt(tester, FakeNotifications(allowed: false)..grantOnRequest = true);
      expect(find.text('Allow reminders?'), findsOneWidget);
      expect(find.textContaining('8:30 pm'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(n.permissionRequests, 1);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Allow reminders?'), findsNothing);
    });

    testWidgets('"Not now" asks Android nothing', (tester) async {
      final n = await pumpPrompt(tester, FakeNotifications(allowed: false));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(n.permissionRequests, 0);
    });

    testWidgets('already allowed, or shown before: no dialog', (tester) async {
      await pumpPrompt(tester, FakeNotifications(allowed: true));
      expect(find.text('Allow reminders?'), findsNothing);
    });

    testWidgets('shown before on this phone: no dialog', (tester) async {
      await pumpPrompt(tester, FakeNotifications(allowed: false), prefs: {kReminderPromptShownKey: true});
      expect(find.text('Allow reminders?'), findsNothing);
    });
  });

  // Same sizes as the Add screen's layout test. Any overflow fails the test.
  group('new screens fit a phone at large text', () {
    FakeRepository fullRepo() => FakeRepository()
      ..bills = [
        _bill(),
        _bill(status: BillStatus.overdue, daysUntil: -40).copyWithName('Home loan EMI from State Bank of India'),
      ]
      ..totals = const MonthTotals(
        expensePaise: 123456700,
        lastExpensePaise: 98765400,
        incomePaise: 250000000,
        lastIncomePaise: 250000000,
        uncategorizedCount: 12,
      )
      ..comparison = [
        for (final c in ['cat-food', 'cat-groc', 'cat-elec'])
          CategoryComparison(
            kind: TxnType.expense,
            categoryId: c,
            categoryName: c,
            color: const Color(0xFF43A047),
            thisMonthPaise: 98765400,
            lastMonthPaise: 12345600,
          ),
      ]
      ..monthlyTotals = [for (var m = 1; m <= 9; m++) _mt(2026, m, 123456700, 250000000)]
      ..monthlyCategoryTotals = [
        for (var m = 1; m <= 9; m++)
          for (var i = 0; i < 8; i++) _ct(m, 'c$i', 'A long category name $i', 12345600 * (i + 1)),
      ];

    for (final (width, scale) in [(412.0, 1.0), (360.0, 1.0), (412.0, 1.3), (360.0, 1.3)]) {
      for (final (name, screen) in <(String, Widget)>[
        ('Reports', const ReportsScreen()),
        ('Bills', const BillsScreen()),
        ('Bill form', const BillFormScreen(billId: 'bill-1')),
        ('Settings', const SettingsScreen()),
      ]) {
        testWidgets('$name at ${width.toInt()} dp, text ×$scale', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpWithFakes(
            tester,
            screen,
            repo: fullRepo(),
            surfaceSize: Size(width, 800),
            overrides: <Override>[currentUserProvider.overrideWithValue(null)],
          );
          for (var i = 0; i < 12; i++) {
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
            await tester.pumpAndSettle();
          }
        });
      }
    }
  });
}
