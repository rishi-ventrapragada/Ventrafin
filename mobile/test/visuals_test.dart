import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/visual_badges.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/features/categories/categories_screen.dart';
import 'package:ventrafin/features/entry/add_screen.dart';
import 'package:ventrafin/features/shell/simple_screens.dart';
import 'package:ventrafin/features/transactions/transactions_screen.dart';

import 'support/fake_repository.dart';

/// Height of one transaction row before icons were added (Increment 2,
/// measured on the same 412×915 surface). Icons must not make rows taller.
const double kRowHeightBeforeIcons = 56.6;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _inRow(String id, Finder f) => find.descendant(of: find.byKey(ValueKey('txn-$id')), matching: f);

void main() {
  group('transactions list', () {
    testWidgets('each row starts with its category icon; Uncategorized and transfers look different',
        (tester) async {
      final repo = FakeRepository()
        ..transactions = [
          testTxn('food', description: 'UPI/SWIGGY/4471023@icici', categoryId: 'cat-food', autoCategorized: true),
          testTxn('elec', description: 'MSEDCL bill', categoryId: 'cat-elec', paymentMethod: PaymentMethod.debit),
          testTxn('none', description: 'Gift for Meena', categoryId: null, paymentMethod: PaymentMethod.cash),
          testTxn('move',
              description: 'ATM', type: TxnType.transfer, accountId: 'acc-bank', toAccountId: 'acc-cash',
              paymentMethod: null),
        ];
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo);

      expect(_inRow('food', find.byIcon(Icons.restaurant)), findsOneWidget);
      expect(_inRow('elec', find.byIcon(Icons.bolt)), findsOneWidget);
      expect(_inRow('none', find.byKey(const Key('uncategorized-avatar'))), findsOneWidget);
      expect(_inRow('none', find.text('Uncategorized')), findsOneWidget);
      expect(_inRow('move', find.byIcon(Icons.swap_horiz)), findsOneWidget);

      // Merchant letter badge from the description.
      expect(_inRow('food', find.byType(MerchantBadge)), findsOneWidget);
      expect(_inRow('food', find.text('S')), findsOneWidget);
      expect(_inRow('none', find.text('G')), findsOneWidget);

      // Account and payment-method icons.
      expect(_inRow('food', find.byIcon(Icons.qr_code_2)), findsOneWidget, reason: 'UPI');
      expect(_inRow('elec', find.byIcon(Icons.atm)), findsOneWidget, reason: 'Debit');
      expect(_inRow('none', find.byIcon(Icons.payments_outlined)), findsNWidgets(2), reason: 'Cash account + cash');
      expect(_inRow('move', find.byIcon(Icons.account_balance)), findsOneWidget, reason: 'from Bank');
    });

    testWidgets('icons do not make rows taller or fit fewer rows on screen', (tester) async {
      final repo = FakeRepository()
        ..transactions = [
          for (var i = 0; i < 30; i++)
            testTxn('t$i',
                description: 'Swiggy dinner $i',
                categoryId: i.isEven ? 'cat-food' : null,
                autoCategorized: i % 3 == 0,
                date: DateTime(2026, 9, 20 - i ~/ 5)),
        ];
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo);

      for (final id in ['t0', 't1', 't3']) {
        expect(tester.getSize(find.byKey(ValueKey('txn-$id'))).height, lessThanOrEqualTo(kRowHeightBeforeIcons),
            reason: id);
      }
      expect(find.byType(Dismissible).evaluate().length, greaterThanOrEqualTo(11),
          reason: '11 rows fitted on this screen before icons were added');
    });
  });

  group('categories screen', () {
    testWidgets('change a category icon and colour from the curated set', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());

      expect(find.descendant(of: find.byKey(const Key('category-cat-food')), matching: find.byIcon(Icons.restaurant)),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('category-cat-food')));
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('category-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'nothing changed yet');

      await tapVisible(tester, find.byKey(const Key('color-#AD1457')));
      await tapVisible(tester, find.byKey(const Key('icon-local_cafe')));
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(repo.categoryUpdates.single, (id: 'cat-food', name: 'Food', iconKey: 'local_cafe', colorHex: '#AD1457'));
      expect(find.text('Food updated'), findsOneWidget);
      // The list re-fetches and shows the new icon.
      expect(find.descendant(of: find.byKey(const Key('category-cat-food')), matching: find.byIcon(Icons.local_cafe)),
          findsOneWidget);
    });

    testWidgets('rename a category', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('category-cat-food')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('category-name')), '  Khana  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category-save')));
      await tester.pumpAndSettle();

      expect(repo.categoryUpdates.single.name, 'Khana', reason: 'sent trimmed');
      expect(repo.categoryUpdates.single.iconKey, 'restaurant', reason: 'icon and colour stay as they were');
      expect(find.text('Food renamed to Khana'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('category-cat-food')), matching: find.text('Khana')),
          findsOneWidget);
    });

    testWidgets('rename: empty, reserved and duplicate names are refused before saving', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('category-cat-food')));
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('category-save'));

      Future<void> typeName(String name) async {
        await tester.enterText(find.byKey(const Key('category-name')), name);
        await tester.pumpAndSettle();
      }

      await typeName('   ');
      expect(find.text('Enter a name'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await typeName('uncategorized');
      expect(find.textContaining('is reserved'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await typeName('groceries');
      expect(find.text('You already have an expense category called "Groceries"'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      // An income category may share a name with an expense one.
      await typeName('Salary');
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      expect(repo.categoryUpdates, isEmpty);
    });

    testWidgets('offline: nothing is sent and the sheet says why', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen(), online: false);
      await tester.tap(find.byKey(const Key('category-cat-groc')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('icon-house')));
      await tester.tap(find.byKey(const Key('category-save')));
      await tester.pumpAndSettle();

      expect(repo.categoryUpdates, isEmpty);
      expect(find.textContaining('no internet connection'), findsOneWidget);
    });
  });

  group('dashboard', () {
    testWidgets('this-month breakdown by category, next to the month comparison', (tester) async {
      final repo = FakeRepository()
        ..totals = const MonthTotals(
            expensePaise: 62000, lastExpensePaise: 25000, incomePaise: 0, lastIncomePaise: 0, uncategorizedCount: 1)
        ..comparison = [
          const CategoryComparison(
              kind: TxnType.expense, categoryId: 'cat-food', categoryName: 'Food', color: Color(0xFFFB8C00),
              thisMonthPaise: 35000, lastMonthPaise: 10000),
          const CategoryComparison(
              kind: TxnType.expense, categoryId: 'cat-groc', categoryName: 'Groceries', color: Color(0xFF43A047),
              thisMonthPaise: 20000, lastMonthPaise: 0),
          const CategoryComparison(
              kind: TxnType.expense, categoryId: null, categoryName: 'Uncategorized', color: Color(0xFF9E9E9E),
              thisMonthPaise: 7000, lastMonthPaise: 0),
          const CategoryComparison(
              kind: TxnType.expense, categoryId: 'cat-med', categoryName: 'Medical', color: Color(0xFFE53935),
              thisMonthPaise: 0, lastMonthPaise: 15000),
          const CategoryComparison(
              kind: TxnType.income, categoryId: 'cat-salary', categoryName: 'Salary', color: Color(0xFF2E7D32),
              thisMonthPaise: 5000000, lastMonthPaise: 0),
        ];
      await pumpWithFakes(tester, const DashboardScreen(), repo: repo);

      final card = find.byKey(const Key('category-breakdown'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      Finder inCard(Finder f) => find.descendant(of: card, matching: f);

      expect(inCard(find.byType(PieChart)), findsOneWidget);
      expect(inCard(find.text('₹620')), findsOneWidget, reason: 'donut centre: total spent this month');
      expect(inCard(find.text('56%')), findsOneWidget, reason: 'Food share');

      // Table: every expense category with spending this month or last.
      expect(inCard(find.byKey(const Key('breakdown-cat-food'))), findsOneWidget);
      expect(inCard(find.byKey(const Key('breakdown-uncategorized'))), findsOneWidget);
      expect(inCard(find.byKey(const Key('breakdown-cat-med'))), findsOneWidget, reason: 'only spent last month');
      expect(inCard(find.text('Salary')), findsNothing, reason: 'income is not spending');
      expect(
          find.descendant(of: find.byKey(const Key('breakdown-cat-food')), matching: find.byIcon(Icons.restaurant)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('breakdown-uncategorized')), matching: find.byType(UncategorizedAvatar)),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('breakdown-cat-food')), matching: find.text('₹250')),
          findsOneWidget, reason: 'change vs last month');
      expect(find.descendant(of: find.byKey(const Key('breakdown-cat-groc')), matching: find.text('new')),
          findsOneWidget);

      // Still next to the existing this-vs-last-month totals.
      expect(find.text('This month'), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const Key('dashboard-spent'))).data, '₹620');
    });

    testWidgets('no spending yet', (tester) async {
      await pumpWithFakes(tester, const DashboardScreen());
      expect(find.text('Nothing spent yet in September 2026.'), findsOneWidget);
    });
  });

  group('entry form', () {
    testWidgets('picker copes with long names at a large font size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = FakeRepository()
        ..categories = [
          ...FakeRepository().categories,
          const Category(
              id: 'cat-mob', name: 'Mobile & Internet', kind: TxnType.expense, color: Color(0xFF3949AB),
              archived: false, iconKey: 'smartphone'),
        ];
      await pumpWithFakes(tester, const AddScreen(), repo: repo);
      // Taller at this font size: the field starts below the fold.
      await tester.scrollUntilVisible(find.byKey(const Key('entry-category')), 200,
          scrollable: find.byType(Scrollable).first);
      await tapVisible(tester, find.byKey(const Key('entry-category')));
      expect(find.byKey(const Key('category-option-cat-mob')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('category picker shows icon tiles and the pick is saved', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const AddScreen());

      // Payment methods carry icons.
      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget, reason: 'category starts on Auto');

      for (final k in ['4', '5', '0']) {
        await tester.tap(find.byKey(Key('keypad-$k')));
        await tester.pump();
      }
      await tapVisible(tester, find.byKey(const Key('method-cash')));
      await tapVisible(tester, find.byKey(const Key('entry-category')));

      expect(find.byKey(const Key('category-option-auto')), findsOneWidget);
      expect(
          find.descendant(of: find.byKey(const Key('category-option-cat-groc')), matching: find.byIcon(Icons.shopping_cart)),
          findsOneWidget);
      expect(find.byKey(const Key('category-option-cat-salary')), findsNothing, reason: 'expense categories only');

      await tester.tap(find.byKey(const Key('category-option-cat-groc')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('entry-category-text'))).data, 'Groceries');

      await tapVisible(tester, find.byKey(const Key('entry-save-another')));
      expect(repo.inserted.single.draft.categoryId, 'cat-groc');
      // The "Just saved" line leads with the category icon.
      expect(find.descendant(of: find.byKey(const Key('just-saved')), matching: find.byIcon(Icons.shopping_cart)),
          findsOneWidget);
      // Category resets to Auto for the next entry.
      expect(tester.widget<Text>(find.byKey(const Key('entry-category-text'))).data, 'Auto');
    });
  });
}
