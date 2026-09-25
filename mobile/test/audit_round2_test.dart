import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventrafin/app.dart';
import 'package:ventrafin/core/category_style.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/core/theme.dart';
import 'package:ventrafin/core/visual_badges.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/features/auth/auth_service.dart';
import 'package:ventrafin/features/auth/login_screen.dart';
import 'package:ventrafin/features/bills/bills_screen.dart';
import 'package:ventrafin/features/entry/add_screen.dart';
import 'package:ventrafin/features/entry/edit_transaction_screen.dart';
import 'package:ventrafin/features/lock/lock_controller.dart';
import 'package:ventrafin/features/lock/setup_lock_screen.dart';
import 'package:ventrafin/features/reminders/reminder_prompt.dart';
import 'package:ventrafin/features/reports/report_data.dart';
import 'package:ventrafin/features/reports/reports_screen.dart';
import 'package:ventrafin/features/settings/settings_screen.dart';
import 'package:ventrafin/features/shell/simple_screens.dart';
import 'package:ventrafin/features/transactions/transactions_screen.dart';
import 'package:ventrafin/features/transactions/txn_filter.dart';
import 'package:ventrafin/router.dart';

import 'support/fake_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Records which way out of the lock was taken.
class _SpyLock extends LockController {
  int signOuts = 0;
  int forgotten = 0;

  @override
  bool build() => false;

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<void> forgotPattern() async => forgotten++;
}

/// Signed in until the fake auth service signs out.
class _Session extends Notifier<bool> {
  @override
  bool build() => true;

  void end() => state = false;
}

final _session = NotifierProvider<_Session, bool>(_Session.new);

class _FakeAuth implements AuthService {
  _FakeAuth(this.ref);

  final Ref ref;
  int signOuts = 0;

  @override
  Future<void> signOut() async {
    signOuts++;
    ref.read(_session.notifier).end();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The whole app, signed in but with no pattern on this phone yet (first
/// run), so the router shows Set up lock.
Future<ProviderContainer> _pumpFirstRun(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({kReminderPromptShownKey: true});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        repositoryProvider.overrideWithValue(FakeRepository()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWith((ref) => ref.watch(_session) ? 'user-1' : null),
        currentUserProvider.overrideWithValue(null),
        authServiceProvider.overrideWith(_FakeAuth.new),
        clockProvider.overrideWithValue(() => fixedClock),
        isOnlineProvider.overrideWithValue(true),
        biometricEnabledProvider.overrideWith((ref) async => false),
        biometricsAvailableProvider.overrideWith((ref) async => false),
      ],
      child: const VentrafinApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(VentrafinApp)));
}

/// The text shown by a single-line [RenderParagraph] was neither wrapped
/// nor cut off (it may be scaled down by a FittedBox, which is fine).
void _expectWhole(WidgetTester tester, Finder finder) {
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final oneLine = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final text = paragraph.text.toPlainText();
    expect(paragraph.size.height, closeTo(oneLine.height, 0.5), reason: '"$text" wrapped');
    expect(paragraph.size.width, greaterThanOrEqualTo(oneLine.width - 0.5), reason: '"$text" was cut off');
    oneLine.dispose();
  }
}

/// Ids of the transaction rows, top to bottom.
List<String> _rowOrder(WidgetTester tester) => [
      for (final e in find.byType(Dismissible).evaluate())
        ((e.widget as Dismissible).key! as ValueKey<String>).value.replaceFirst('txn-', ''),
    ];

Future<void> _pickMenu(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const Key('txn-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Bill _bill({bool reminder = true}) => Bill(
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
      daysUntil: 3,
      status: BillStatus.dueSoon,
      overdueCount: 0,
    );

final _big = const MonthTotals(
  expensePaise: 123456700, // ₹12,34,567
  lastExpensePaise: 98765400, // ₹9,87,654
  incomePaise: 250000000,
  lastIncomePaise: 250000000,
  uncategorizedCount: 0,
);

void main() {
  // -------------------------------------------------------------------------
  group('NAV-3: a way out of first-run lock setup', () {
    testWidgets('"Not you? Sign out" signs out normally (not "forgot pattern")', (tester) async {
      await pumpWithFakes(
        tester,
        const SetupLockScreen(),
        overrides: <Override>[
          lockControllerProvider.overrideWith(_SpyLock.new),
          biometricsAvailableProvider.overrideWith((ref) async => false),
          currentUserProvider.overrideWithValue(null),
        ],
      );
      await tester.tap(find.text('Not you? Sign out'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(SetupLockScreen)));
      final spy = container.read(lockControllerProvider.notifier) as _SpyLock;
      expect(spy.signOuts, 1);
      expect(spy.forgotten, 0);
    });

    testWidgets('not offered when changing the pattern', (tester) async {
      await pumpWithFakes(
        tester,
        const SetupLockScreen(requireCurrent: true),
        overrides: <Override>[
          lockControllerProvider.overrideWith(_SpyLock.new),
          biometricsAvailableProvider.overrideWith((ref) async => false),
          currentUserProvider.overrideWithValue(null),
        ],
      );
      expect(find.text('Not you? Sign out'), findsNothing);
    });

    testWidgets('in the app: first run -> Sign out -> back to the sign-in screen', (tester) async {
      final container = await _pumpFirstRun(tester);
      expect(location(container), '/setup-lock');
      expect(find.byType(SetupLockScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('setup-sign-out')));
      await tester.pumpAndSettle();
      expect((container.read(authServiceProvider) as _FakeAuth).signOuts, 1);
      expect(location(container), '/login');
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('Dashboard (DASH-1, DASH-2, DASH-3)', () {
    testWidgets("this month's spending is the headline; both columns compact", (tester) async {
      await pumpWithFakes(tester, const DashboardScreen(), repo: FakeRepository()..totals = _big);
      final headline = tester.widget<Text>(find.byKey(const Key('dashboard-spent')));
      expect(headline.data, '₹12,34,567');
      final tableSpent = find.text('₹12,34,567').evaluate().map((e) => e.widget as Text).firstWhere((t) => t != headline);
      expect(headline.style!.fontSize!, greaterThan(tableSpent.style!.fontSize! * 1.5), reason: 'stands out');
      expect(find.text('₹9,87,654'), findsOneWidget, reason: 'last month, compact');
      expect(find.text('₹25,00,000'), findsNWidgets(2), reason: 'income this month and last, both compact');
      expect(find.textContaining('.00'), findsNothing, reason: 'no full format left');
    });

    testWidgets("the actions sit above the category breakdown", (tester) async {
      await pumpWithFakes(tester, const DashboardScreen());
      expect(
        tester.getTopLeft(find.byKey(const Key('dashboard-add'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('category-breakdown'))).dy),
      );
    });

    for (final scale in [1.3, 1.5]) {
      testWidgets('amounts stay on one line at 360 dp, text ×$scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpWithFakes(
          tester,
          const DashboardScreen(),
          repo: FakeRepository()..totals = _big,
          surfaceSize: const Size(360, 800),
        );
        for (final amount in ['₹12,34,567', '₹9,87,654', '₹25,00,000', '₹12,65,433', '₹15,12,346']) {
          _expectWhole(tester, find.text(amount));
        }
      });
    }
  });

  // -------------------------------------------------------------------------
  group('Transactions rows (TX-2, TX-4)', () {
    testWidgets('a transfer with a payment method fits 360 dp and leaves the method out', (tester) async {
      final repo = FakeRepository()
        ..accounts = const [
          Account(id: 'acc-bank', name: 'State Bank savings', type: AccountType.bank),
          Account(id: 'acc-cc', name: 'HDFC Credit Card', type: AccountType.credit),
          Account(id: 'acc-cash', name: 'Cash', type: AccountType.cash),
        ]
        ..transactions = [
          testTxn('t1', description: 'Card bill payment', type: TxnType.transfer, accountId: 'acc-bank',
              toAccountId: 'acc-cc', paymentMethod: PaymentMethod.upi),
          testTxn('t2', description: 'Swiggy', paymentMethod: PaymentMethod.upi),
        ];
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo, surfaceSize: const Size(360, 800));
      expect(find.descendant(of: find.byKey(const ValueKey('txn-t1')), matching: find.text('UPI')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('txn-t2')), matching: find.text('UPI')), findsOneWidget);
    });

    testWidgets('the "auto" marker uses onSurfaceVariant', (tester) async {
      final repo = FakeRepository()..transactions = [testTxn('t1', autoCategorized: true)];
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo);
      final auto = tester.widget<Text>(find.byKey(const Key('txn-auto-t1')));
      final context = tester.element(find.byKey(const Key('txn-auto-t1')));
      expect(auto.style?.color, Theme.of(context).colorScheme.onSurfaceVariant);
    });

    test('onSurfaceVariant reads at 4.5:1 on every surface, highlighted rows included, in all six themes', () {
      for (final t in kThemes) {
        final ink = buildAppTheme(t).colorScheme.onSurfaceVariant;
        for (final s in t.surfaces) {
          expect(contrastRatio(ink, s), greaterThanOrEqualTo(4.5), reason: '${t.name}: on ${toHexColor(s)}');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Transactions sort (PRD-3)', () {
    FakeRepository repo() {
      final september = [
        testTxn('big', description: 'Rent', amountPaise: 2500000, date: DateTime(2026, 9, 5)),
        testTxn('mid', description: 'Swiggy dinner', amountPaise: 45000, date: DateTime(2026, 9, 20)),
        testTxn('small', description: 'Tea', amountPaise: 2000, date: DateTime(2026, 9, 12)),
        testTxn('pay', description: 'Salary', type: TxnType.income, categoryId: 'cat-salary', amountPaise: 9000000,
            paymentMethod: null, date: DateTime(2026, 9, 1)),
      ];
      return FakeRepository()
        ..transactions = september
        ..allTransactions = [
          ...september,
          testTxn('old', description: 'Swiggy lunch', amountPaise: 30000, date: DateTime(2025, 12, 30)),
        ];
    }

    double y(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

    testWidgets('newest first by default; oldest first keeps the day groups, reversed', (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo());
      expect(_rowOrder(tester), ['mid', 'small', 'big', 'pay']);
      expect(y(tester, 'Sun, 20 Sep 2026'), lessThan(y(tester, 'Sat, 5 Sep 2026')));
      expect(find.byKey(const Key('active-filters')), findsNothing, reason: 'nothing to say by default');

      await _pickMenu(tester, 'filter-sort-oldest');
      expect(_rowOrder(tester), ['pay', 'big', 'small', 'mid']);
      expect(y(tester, 'Sat, 5 Sep 2026'), lessThan(y(tester, 'Sun, 20 Sep 2026')), reason: 'still grouped by day');
      expect(tester.widget<Text>(find.byKey(const Key('active-filters'))).data, 'Oldest first');
    });

    testWidgets('largest amount first: one flat list, each row with its date', (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo());
      await _pickMenu(tester, 'filter-sort-largest');
      expect(_rowOrder(tester), ['pay', 'big', 'mid', 'small']);
      expect(find.text('Sun, 20 Sep 2026'), findsNothing, reason: 'no day headers');
      expect(tester.widget<Text>(find.byKey(const Key('txn-date-mid'))).data, '20 Sep');

      await _pickMenu(tester, 'filter-sort-smallest');
      expect(_rowOrder(tester), ['small', 'mid', 'big', 'pay']);
    });

    testWidgets('works with the filters and the search; Clear resets the order too', (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo());
      await _pickMenu(tester, 'filter-sort-largest');
      await _pickMenu(tester, 'filter-type-expense');
      expect(_rowOrder(tester), ['big', 'mid', 'small']);
      expect(
        tester.widget<Text>(find.byKey(const Key('active-filters'))).data,
        'Largest amount first · Showing only: Expenses',
      );

      // The search (every month) keeps the order; an older year shows it.
      await tester.tap(find.byKey(const Key('txn-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('txn-search')), 'swiggy');
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['mid', 'old']);
      expect(tester.widget<Text>(find.byKey(const Key('txn-date-old'))).data, '30 Dec 2025');
      await tester.tap(find.byKey(const Key('txn-search-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-clear')));
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['mid', 'small', 'big', 'pay']);
      expect(find.byKey(const Key('active-filters')), findsNothing);
    });

    test('ties: equal amounts keep the newer entry first', () {
      final a = testTxn('a', amountPaise: 100, date: DateTime(2026, 9, 1));
      final b = testTxn('b', amountPaise: 100, date: DateTime(2026, 9, 3));
      final c = testTxn('c', amountPaise: 100, date: DateTime(2026, 9, 3), createdAt: DateTime(2026, 9, 3, 12));
      expect(sortTxns([a, b, c], TxnSort.largest).map((t) => t.id), ['c', 'b', 'a']);
      expect(sortTxns([a, b, c], TxnSort.smallest).map((t) => t.id), ['c', 'b', 'a']);
      expect(sortTxns([a, b, c], TxnSort.newest).map((t) => t.id), ['c', 'b', 'a']);
      expect(sortTxns([a, b, c], TxnSort.oldest).map((t) => t.id), ['a', 'b', 'c']);
    });
  });

  // -------------------------------------------------------------------------
  group('Entry form (TX-3, ADD-1, ADD-2)', () {
    testWidgets('editing an Uncategorized entry says "Uncategorized", not "Auto"', (tester) async {
      final repo = FakeRepository()..transactions = [testTxn('t1', categoryId: null)];
      await pumpWithFakes(tester, const EditTransactionScreen(id: 't1'), repo: repo);
      expect(tester.widget<Text>(find.byKey(const Key('entry-category-text'))).data, 'Uncategorized');
      expect(find.text('Auto'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('entry-category')));
      await tester.tap(find.byKey(const Key('entry-category')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category-option-auto')), findsNothing);
      final tile = find.byKey(const Key('category-option-uncategorized'));
      expect(find.descendant(of: tile, matching: find.text('Uncategorized')), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byType(UncategorizedAvatar)), findsOneWidget);
    });

    testWidgets('editing: picking the no-category tile shows Uncategorized', (tester) async {
      final repo = FakeRepository()..transactions = [testTxn('t1')];
      await pumpWithFakes(tester, const EditTransactionScreen(id: 't1'), repo: repo);
      expect(tester.widget<Text>(find.byKey(const Key('entry-category-text'))).data, 'Food');
      await tester.ensureVisible(find.byKey(const Key('entry-category')));
      await tester.tap(find.byKey(const Key('entry-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category-option-uncategorized')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('entry-category-text'))).data, 'Uncategorized');
    });

    testWidgets('"Paid by (optional)" for income and transfers; "Yesterday" chip', (tester) async {
      await pumpWithFakes(tester, const AddScreen());
      expect(find.text('Paid by'), findsOneWidget);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(find.text('Paid by (optional)'), findsOneWidget);
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      expect(find.text('Paid by (optional)'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('entry-date-yesterday')));
      await tester.tap(find.text('Yesterday'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('entry-date-text'))).data, 'Yesterday, 24 Sep');
      expect(find.text('Yest.'), findsNothing);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('the date chips fit 360 dp at text ×$scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpWithFakes(tester, const AddScreen(), surfaceSize: const Size(360, 800));
        await tester.ensureVisible(find.byKey(const Key('entry-date-yesterday')));
        await tester.pumpAndSettle();
        for (final key in ['entry-date', 'entry-date-today', 'entry-date-yesterday']) {
          final rect = tester.getRect(find.byKey(Key(key)));
          expect(rect.left, greaterThanOrEqualTo(0), reason: key);
          expect(rect.right, lessThanOrEqualTo(360), reason: key);
        }
        _expectWhole(tester, find.text('Yesterday'));
      });
    }
  });

  // -------------------------------------------------------------------------
  group('Bills (BILL-4, BILL-5)', () {
    testWidgets('the bell says what it did, and Undo puts it back', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const BillsScreen(), repo: FakeRepository()..bills = [_bill()]);
      await tester.tap(find.byKey(const Key('bill-reminder-bill-1')));
      await tester.pumpAndSettle();
      expect(find.text('No reminders for BESCOM'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.reminderToggles, [(id: 'bill-1', enabled: false), (id: 'bill-1', enabled: true)]);
    });

    test('the FAB is solid primary with white on it, in every theme', () {
      for (final t in kThemes) {
        final fab = buildAppTheme(t).floatingActionButtonTheme;
        expect(fab.backgroundColor, t.primary, reason: t.name);
        expect(fab.foregroundColor, Colors.white, reason: t.name);
      }
    });

    testWidgets('"Add bill" is drawn in the theme primary (Sunflower)', (tester) async {
      final sunflower = themeTokensFor('sunflower');
      await pumpWithFakes(tester, const BillsScreen(), theme: buildAppTheme(sunflower));
      final material = tester.widget<Material>(
        find.descendant(of: find.byKey(const Key('add-bill')), matching: find.byType(Material)).first,
      );
      expect(material.color, sunflower.primary);
    });
  });

  // -------------------------------------------------------------------------
  group('Reports (REP-1, REP-2, REP-3, REP-4)', () {
    FakeRepository bigRepo() => FakeRepository()
      ..totals = _big
      ..comparison = [
        for (final c in ['cat-food', 'cat-groc', 'cat-elec'])
          CategoryComparison(
            kind: TxnType.expense,
            categoryId: c,
            categoryName: c,
            color: const Color(0xFF43A047),
            thisMonthPaise: 9876543200, // ₹9,87,65,432
            lastMonthPaise: 12345600,
          ),
      ]
      ..monthlyTotals = [
        for (var m = 4; m <= 9; m++)
          MonthlyTotal(
            month: YearMonth(2026, m),
            expensePaise: 9876543200,
            incomePaise: 12345678900,
            expenseCount: 3,
            incomeCount: 1,
            uncategorizedCount: 0,
          ),
      ]
      ..monthlyCategoryTotals = [
        for (var m = 4; m <= 9; m++)
          for (var i = 0; i < 7; i++)
            MonthlyCategoryTotal(
              month: YearMonth(2026, m),
              kind: TxnType.expense,
              categoryId: 'c$i',
              categoryName: 'Category $i',
              color: const Color(0xFFFB8C00),
              count: 2,
              totalPaise: 1234567800 * (i + 1),
            ),
      ];

    testWidgets('numbers shrink to fit their cells instead of being cut off (360 dp, text ×1.5)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpWithFakes(tester, const ReportsScreen(), repo: bigRepo(), surfaceSize: const Size(360, 800),
          overrides: <Override>[currentUserProvider.overrideWithValue(null)]);
      final amounts = find.descendant(
        of: find.byKey(const Key('report-categories-expense')),
        matching: find.textContaining('₹'),
      );
      _expectWhole(
        tester,
        find.descendant(of: find.byKey(const Key('report-month-summary')), matching: find.textContaining('₹')),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('report-expense-cat-food')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(amounts, findsWidgets);
      _expectWhole(tester, amounts);
    });

    testWidgets('pivot rows grow with the font size (text ×1.5) and the numbers still fit', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpWithFakes(tester, const ReportsScreen(), repo: bigRepo(), surfaceSize: const Size(360, 800),
          overrides: <Override>[currentUserProvider.overrideWithValue(null)]);
      final row = find.byKey(const Key('pivot-row-c0'));
      await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final height = tester.getSize(row).height;
      expect(height, closeTo(28 * 1.5, 0.01));
      final name = find.descendant(of: row, matching: find.text('Category 0'));
      expect(tester.getSize(name).height, lessThanOrEqualTo(height), reason: 'the name fits its row');
      // Rows follow each other without overlapping (largest first: c1
      // is just above c0).
      expect(
        tester.getTopLeft(row).dy,
        closeTo(tester.getTopLeft(find.byKey(const Key('pivot-row-c1'))).dy + height, 0.01),
      );
      _expectWhole(
        tester,
        find.descendant(of: find.byKey(const Key('pivot-scroll')), matching: find.textContaining('₹')),
      );
    });

    test('"Other" is #7F8C93, at least 3:1 on every surface of every theme', () {
      expect(kOtherSeriesColor, const Color(0xFF7F8C93));
      for (final t in kThemes) {
        for (final s in t.surfaces) {
          expect(contrastRatio(kOtherSeriesColor, s), greaterThanOrEqualTo(3), reason: '${t.name} ${toHexColor(s)}');
        }
      }
    });

    testWidgets('Other: chart legend swatch in the new grey', (tester) async {
      await pumpWithFakes(tester, const ReportsScreen(), repo: bigRepo(),
          overrides: <Override>[currentUserProvider.overrideWithValue(null)]);
      final legend = find.text('Other (2)');
      await tester.scrollUntilVisible(legend, 300, scrollable: find.byType(Scrollable).first);
      final swatch = tester.widget<Container>(
        find.descendant(of: find.ancestor(of: legend, matching: find.byType(Row)).first, matching: find.byType(Container)),
      );
      expect((swatch.decoration! as BoxDecoration).color, kOtherSeriesColor);
    });

    testWidgets('a caption under the month summary explains Net, Saved, #, vs last and Avg', (tester) async {
      await pumpWithFakes(tester, const ReportsScreen(), repo: bigRepo(),
          overrides: <Override>[currentUserProvider.overrideWithValue(null)]);
      final caption = find.descendant(
        of: find.byKey(const Key('report-month-summary')),
        matching: find.byKey(const Key('report-caption')),
      );
      expect(caption, findsOneWidget);
      final text = tester.widget<Text>(find.descendant(of: caption, matching: find.byType(Text))).data!;
      expect(
        text,
        'Net = income minus spending. Saved = the part of income not spent, as a percentage.\n'
        '# = number of entries. vs last = change from the month before. Avg = monthly average over the months shown.',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Settings (SET-2)', () {
    testWidgets('daily reminder off: the time row stays readable; only the time is greyed and fixed', (tester) async {
      final repo = FakeRepository()
        ..profile = const Profile(
          theme: 'ocean',
          dailyReminderEnabled: false,
          dailyReminderTime: kDefaultDailyReminderTime,
          billRemindersEnabled: true,
          billReminderDaysBefore: kDefaultBillReminderDaysBefore,
        );
      await pumpWithFakes(tester, const SettingsScreen(), repo: repo,
          overrides: <Override>[currentUserProvider.overrideWithValue(null)]);
      final tile = find.byKey(const Key('daily-reminder-time'));
      expect(tester.widget<ListTile>(tile).enabled, isTrue);

      final page = themeTokensFor('ocean').page;
      for (final text in ['Reminder time', 'India time']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: tile, matching: find.text(text)));
        final color = paragraph.text.style!.color!;
        expect(contrastRatio(Color.alphaBlend(color, page), page), greaterThanOrEqualTo(4.5), reason: text);
      }
      final context = tester.element(tile);
      expect(
        tester.widget<Text>(find.byKey(const Key('daily-reminder-time-value'))).style?.color,
        Theme.of(context).disabledColor,
      );

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing, reason: "can't be changed while the reminder is off");
    });

    testWidgets('daily reminder on: tapping the row picks the time', (tester) async {
      await pumpWithFakes(tester, const SettingsScreen(),
          overrides: <Override>[currentUserProvider.overrideWithValue(null)]);
      await tester.tap(find.byKey(const Key('daily-reminder-time')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });
  });
}

/// The route of the top screen (a copy of the app harness's, which pumps a
/// user who already has a pattern).
String location(ProviderContainer container) => container.read(routerProvider).state.matchedLocation;
