import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventrafin/core/errors.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/features/accounts/accounts_screen.dart';
import 'package:ventrafin/features/bills/bill_form_screen.dart';
import 'package:ventrafin/features/categories/categories_screen.dart';
import 'package:ventrafin/features/entry/add_screen.dart';
import 'package:ventrafin/features/entry/edit_transaction_screen.dart';

import 'support/fake_repository.dart';

const _old = Account(id: 'acc-old', name: 'Old SBI', type: AccountType.bank, archived: true);
const _oldCategory = Category(
    id: 'cat-old', name: 'Tuition', kind: TxnType.expense, color: Color(0xFF3949AB), archived: true, iconKey: 'school');

FakeRepository _withArchived() => FakeRepository()
  ..accounts = [...FakeRepository().accounts, _old]
  ..categories = [...FakeRepository().categories, _oldCategory];

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The account ids a dropdown offers.
List<String?> _options(WidgetTester tester, Key key) => tester
    .widget<DropdownButton<String>>(find.descendant(of: find.byKey(key), matching: find.byType(DropdownButton<String>)))
    .items!
    .map((i) => i.value)
    .toList();

Future<void> _typeName(WidgetTester tester, Key key, String name) async {
  await tester.enterText(find.byKey(key), name);
  await tester.pumpAndSettle();
}

void main() {
  group('Accounts', () {
    testWidgets('active accounts first, archived ones after with Restore; no "later update" note', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const AccountsScreen(), repo: _withArchived());
      expect(find.text('Archived'), findsOneWidget);
      expect(find.textContaining('later update'), findsNothing);
      expect(tester.getTopLeft(find.text('Credit Card')).dy, lessThan(tester.getTopLeft(find.text('Archived')).dy));
      expect(tester.getTopLeft(find.text('Old SBI')).dy, greaterThan(tester.getTopLeft(find.text('Archived')).dy));

      await tester.tap(find.byKey(const Key('restore-account-acc-old')));
      await tester.pumpAndSettle();
      expect(repo.accountArchives.single, (id: 'acc-old', archived: false));
      expect(find.text('Restored Old SBI'), findsOneWidget);
      expect(find.text('Archived'), findsNothing);
    });

    testWidgets('add: the name is checked before saving, then saved with a client id', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const AccountsScreen(), repo: _withArchived());
      await tester.tap(find.byKey(const Key('add-account')));
      await tester.pumpAndSettle();
      expect(find.text('Add account'), findsNWidgets(3), reason: 'the button, the sheet title and its save button');

      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);

      await _typeName(tester, const Key('account-name'), '  bank ');
      expect(find.text('You already have an account called "Bank"'), findsOneWidget);
      await _typeName(tester, const Key('account-name'), 'OLD sbi');
      expect(find.text('You already have an account called "Old SBI" (archived)'), findsOneWidget);
      // The field stops at 60 characters; the rule itself mirrors the database.
      expect(accountNameError('x' * 61, existing: const []), 'Keep it to 60 characters or fewer');
      expect(accountNameError('x' * 60, existing: const []), isNull);
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();
      expect(repo.accountInserts, isEmpty);

      await _typeName(tester, const Key('account-name'), '  HDFC credit card ');
      await tester.tap(find.descendant(of: find.byKey(const Key('account-type')), matching: find.text('Credit card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();

      final added = repo.accountInserts.single;
      expect(added.id, hasLength(36));
      expect(added.name, 'HDFC credit card');
      expect(added.type, AccountType.credit);
      expect(find.text('Added HDFC credit card'), findsOneWidget);
      expect(find.byKey(Key('account-${added.id}')), findsOneWidget);
    });

    testWidgets('edit: rename and change the type', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const AccountsScreen());
      await tester.tap(find.byKey(const Key('account-acc-bank')));
      await tester.pumpAndSettle();
      expect(find.text('Edit account'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('account-save'))).onPressed, isNull,
          reason: 'nothing changed yet');

      await _typeName(tester, const Key('account-name'), 'SBI savings');
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();
      expect(repo.accountUpdates.single, (id: 'acc-bank', name: 'SBI savings', type: AccountType.bank));
      expect(find.text('Saved SBI savings'), findsOneWidget);
    });

    testWidgets('archive asks first, then moves the account to Archived', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const AccountsScreen());
      await tester.tap(find.byKey(const Key('account-acc-cash')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-archive')));
      await tester.pumpAndSettle();

      expect(find.text('Archive Cash?'), findsOneWidget);
      expect(
          find.text('It disappears from the account pickers. Its transactions and bills keep it, '
              'and you can restore it any time.'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-archive')));
      await tester.pumpAndSettle();
      expect(repo.accountArchives.single, (id: 'acc-cash', archived: true));
      expect(find.text('Archived Cash'), findsOneWidget);
      expect(find.byKey(const Key('restore-account-acc-cash')), findsOneWidget);
    });

    testWidgets('the last active account cannot be archived', (tester) async {
      final repo = FakeRepository()
        ..accounts = const [Account(id: 'acc-cash', name: 'Cash', type: AccountType.cash), _old];
      await pumpWithFakes(tester, const AccountsScreen(), repo: repo);
      await tester.tap(find.byKey(const Key('account-acc-cash')));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('account-archive'))).onPressed, isNull);
      expect(find.text('Keep at least one active account.'), findsOneWidget);
    });

    testWidgets('the database refusing the last active account reads plainly', (tester) async {
      final repo = FakeRepository()
        ..failNextAccountWriteWith = const PostgrestException(
          message: 'Keep at least one active account.',
          code: '23514',
        );
      await pumpWithFakes(tester, const AccountsScreen(), repo: repo);
      await tester.tap(find.byKey(const Key('account-acc-cash')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-archive')));
      await tester.pumpAndSettle();
      expect(find.text('Not archived. Keep at least one active account.'), findsOneWidget);
    });

    testWidgets('a failed load says why, with Retry', (tester) async {
      final repo = FakeRepository()..failNextFetchAccountsWith = const PostgrestException(message: 'x', code: '42501');
      await pumpWithFakes(tester, const AccountsScreen(), repo: repo);
      expect(find.text("You don't have permission to do that. Try signing out and back in."), findsOneWidget);
      expect(find.textContaining('PostgrestException'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Credit Card'), findsOneWidget);
    });

    test('rows without the archived column (before the migration) count as active', () {
      expect(Account.fromRow({'id': 'a', 'name': 'Cash', 'type': 'cash'}).archived, isFalse);
      expect(Account.fromRow({'id': 'a', 'name': 'Cash', 'type': 'cash', 'archived': true}).archived, isTrue);
    });

    test('describeError: the last-account refusal, and other 23514s unchanged', () {
      expect(
        describeError(const PostgrestException(message: 'Keep at least one active account.', code: '23514')),
        'Keep at least one active account.',
      );
      expect(
        describeError(const PostgrestException(message: 'x', code: '23514', details: 'constraint accounts_one_active')),
        'Keep at least one active account.',
      );
      expect(
        describeError(const PostgrestException(message: 'new row violates check constraint', code: '23514')),
        startsWith('Some values were not accepted'),
      );
    });
  });

  group('pickers for new entries hide archived accounts and categories', () {
    testWidgets('Add: account and transfer target; a remembered archived account falls back', (tester) async {
      await pumpWithFakes(tester, const AddScreen(), repo: _withArchived(), prefs: {'entry.lastAccountId': 'acc-old'});
      expect(_options(tester, const Key('entry-account')), ['acc-bank', 'acc-cash', 'acc-cc']);
      final selected = tester
          .widget<DropdownButton<String>>(
              find.descendant(of: find.byKey(const Key('entry-account')), matching: find.byType(DropdownButton<String>)))
          .value;
      expect(selected, 'acc-cash', reason: 'the remembered account is archived: Cash instead');

      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      expect(_options(tester, const Key('entry-to-account')), ['acc-bank', 'acc-cash', 'acc-cc']);

      // Category picker: the archived category isn't offered.
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('entry-category')));
      expect(find.byKey(const Key('category-option-cat-food')), findsOneWidget);
      expect(find.byKey(const Key('category-option-cat-old')), findsNothing);
    });

    testWidgets('Edit: an archived account or category stays as the current value, marked (archived)',
        (tester) async {
      final repo = _withArchived()
        ..transactions = [testTxn('t1', accountId: 'acc-old', categoryId: 'cat-old')];
      await pumpWithFakes(tester, const EditTransactionScreen(id: 't1'), repo: repo);
      expect(_options(tester, const Key('entry-account')), ['acc-bank', 'acc-cash', 'acc-cc', 'acc-old']);
      expect(find.text('Old SBI (archived)'), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const Key('entry-category-text'))).data, 'Tuition (archived)');

      await tapVisible(tester, find.byKey(const Key('entry-category')));
      expect(find.text('Tuition (archived)'), findsWidgets, reason: 'the current value stays pickable');
    });

    testWidgets('Bill form: archived accounts hidden for a new bill, kept (marked) on an existing one',
        (tester) async {
      final repo = FakeRepository()
        ..accounts = [
          const Account(id: 'acc-sbi', name: 'SBI', type: AccountType.bank, archived: true),
          ...FakeRepository().accounts,
        ];
      await pumpWithFakes(tester, const BillFormScreen(), repo: repo);
      final dropdown = find.byWidgetPredicate((w) => w is DropdownButton<String>);
      expect(tester.widget<DropdownButton<String>>(dropdown).items!.map((i) => i.value),
          ['acc-bank', 'acc-cash', 'acc-cc']);
      expect(tester.widget<DropdownButton<String>>(dropdown).value, 'acc-bank',
          reason: 'the first active bank account, not the archived one');
    });

    testWidgets('Bill form: an existing bill on an archived account keeps it', (tester) async {
      final repo = _withArchived()
        ..bills = [
          Bill(
            id: 'bill-1',
            name: 'BESCOM',
            kind: BillKind.utility,
            amountPaise: 145000,
            dueDay: 28,
            accountId: 'acc-old',
            categoryId: null,
            reminderEnabled: true,
            paidThroughMonth: const YearMonth(2026, 8),
            nextDueDate: DateTime(2026, 9, 28),
            daysUntil: 3,
            status: BillStatus.dueSoon,
            overdueCount: 0,
          ),
        ];
      await pumpWithFakes(tester, const BillFormScreen(billId: 'bill-1'), repo: repo);
      final dropdown = find.byWidgetPredicate((w) => w is DropdownButton<String>);
      expect(tester.widget<DropdownButton<String>>(dropdown).items!.map((i) => i.value),
          ['acc-bank', 'acc-cash', 'acc-cc', 'acc-old']);
      expect(find.text('Old SBI (archived)'), findsWidgets);
    });
  });

  group('Categories', () {
    testWidgets('add from a section: that kind preselected, same name rules, only name and kind sent',
        (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());
      expect(find.textContaining('later update'), findsNothing);

      await tester.tap(find.byKey(const Key('add-category-income')));
      await tester.pumpAndSettle();
      expect(
          find.text('Ventrafin picks an icon and colour from the name. Change them afterwards by opening the category.'),
          findsOneWidget);
      final kind = tester.widget<SegmentedButton<TxnType>>(find.byKey(const Key('new-category-kind')));
      expect(kind.selected, {TxnType.income});

      await tester.tap(find.byKey(const Key('new-category-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await _typeName(tester, const Key('new-category-name'), 'salary');
      expect(find.text('You already have an income category called "Salary"'), findsOneWidget);
      await _typeName(tester, const Key('new-category-name'), 'Uncategorized');
      expect(find.textContaining('is reserved'), findsOneWidget);

      await _typeName(tester, const Key('new-category-name'), ' Freelance ');
      await tester.tap(find.byKey(const Key('new-category-save')));
      await tester.pumpAndSettle();
      expect(repo.categoryInserts.single, (name: 'Freelance', kind: TxnType.income));
      expect(find.text('Added Freelance'), findsOneWidget);
      expect(find.text('Freelance'), findsOneWidget);
    });

    testWidgets('archive asks first; archived ones are listed last with Restore', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('category-cat-food')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('category-archive')));

      expect(find.text('Archive Food?'), findsOneWidget);
      expect(
          find.text('It disappears from the category pickers and auto-categorization stops using it. '
              'Its past transactions keep it, and you can restore it any time.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-archive')));
      await tester.pumpAndSettle();
      expect(repo.categoryArchives.single, (id: 'cat-food', archived: true));
      expect(find.text('Archived Food'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      expect(find.text('Expense · archived'), findsOneWidget);

      await tester.tap(find.byKey(const Key('restore-category-cat-food')));
      await tester.pumpAndSettle();
      expect(repo.categoryArchives.last, (id: 'cat-food', archived: false));
      expect(find.text('Restored Food'), findsOneWidget);
      expect(find.text('Archived'), findsNothing);
    });

    testWidgets('a failed load says why, with Retry', (tester) async {
      final repo = FakeRepository()..failNextFetchCategoriesWith = const PostgrestException(message: 'x', code: '42501');
      await pumpWithFakes(tester, const CategoriesScreen(), repo: repo);
      expect(find.text("You don't have permission to do that. Try signing out and back in."), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category-cat-food')), findsOneWidget);
    });
  });
}
