import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/features/bills/bill_form_screen.dart';
import 'package:ventrafin/features/bills/bills_screen.dart';
import 'package:ventrafin/features/entry/add_screen.dart';
import 'package:ventrafin/features/entry/edit_transaction_screen.dart';
import 'package:ventrafin/features/lock/lock_controller.dart';
import 'package:ventrafin/features/lock/lock_screen.dart';
import 'package:ventrafin/features/lock/setup_lock_screen.dart';
import 'package:ventrafin/features/reports/reports_screen.dart';
import 'package:ventrafin/features/settings/settings_screen.dart';
import 'package:ventrafin/features/shell/simple_screens.dart';
import 'package:ventrafin/features/transactions/transactions_screen.dart';

import 'support/app_harness.dart';
import 'support/fake_repository.dart';

Bill _bill() => Bill(
  id: 'bill-1',
  name: 'BESCOM',
  kind: BillKind.utility,
  amountPaise: 145000,
  dueDay: 28,
  accountId: 'acc-bank',
  categoryId: 'cat-elec',
  reminderEnabled: true,
  paidThroughMonth: const YearMonth(2026, 8),
  nextDueDate: DateTime(2026, 9, 28),
  daysUntil: 3,
  status: BillStatus.dueSoon,
  overdueCount: 0,
);

FakeRepository _repo() => FakeRepository()
  ..transactions = [testTxn('t1', description: 'Swiggy dinner'), testTxn('t2', description: 'DMart', categoryId: null)]
  ..bills = [_bill()];

Finder get _discardDialog => find.text('Discard changes?');

int _tab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar, skipOffstage: false)).selectedIndex;

void main() {
  group('Android back', () {
    testWidgets('on a tab\'s first screen it goes to the Dashboard; on the Dashboard it leaves the app',
        (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());
      expect(find.byType(DashboardScreen), findsOneWidget);

      for (final (label, screen) in <(String, Type)>[
        ('Transactions', TransactionsScreen),
        ('Add', AddScreen),
        ('Bills', BillsScreen),
        ('More', MoreScreen),
      ]) {
        await tapTab(tester, label);
        expect(find.byType(screen), findsOneWidget, reason: label);

        expect(await pressBack(tester), isTrue, reason: 'back on $label is handled by the app');
        expect(find.byType(DashboardScreen), findsOneWidget, reason: 'back on $label goes to the Dashboard');
        expect(_tab(tester), 0);
        expect(location(container), '/dashboard');
      }

      expect(await pressBack(tester), isFalse, reason: 'back on the Dashboard leaves the app');
    });

    testWidgets('inside a tab it pops that tab\'s own screens first', (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());

      await tapTab(tester, 'More');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      expect(await pressBack(tester), isTrue);
      expect(find.byType(MoreScreen), findsOneWidget, reason: 'back from Settings returns to More');
      expect(_tab(tester), 4);

      expect(await pressBack(tester), isTrue);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(location(container), '/dashboard');
    });

    testWidgets('a screen pushed over a tab (Edit transaction) closes back to that tab', (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());

      await tapTab(tester, 'Transactions');
      await tester.tap(find.text('Swiggy dinner'));
      await tester.pumpAndSettle();
      expect(find.byType(EditTransactionScreen), findsOneWidget);
      expect(location(container), '/transactions/t1');

      expect(await pressBack(tester), isTrue);
      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(find.byType(TransactionsScreen), findsOneWidget, reason: 'back to the list, not the Dashboard');
      expect(_tab(tester), 1);

      expect(await pressBack(tester), isTrue);
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });

  group('jumps between sections return where they started', () {
    testWidgets('Dashboard -> Reports -> back is the Dashboard', (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());
      await tester.tap(find.byKey(const Key('dashboard-reports')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(location(container), '/dashboard/reports');

      expect(await pressBack(tester), isTrue);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ReportsScreen), findsNothing);
      expect(_tab(tester), 0);
    });

    testWidgets('Bills bell -> Settings -> "Your bills" -> back, back is Bills', (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Bills');

      await tester.tap(find.byKey(const Key('bills-reminder-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(location(container), '/bills/settings');

      // From that Settings, on to its bills list, then all the way back.
      final yourBills = find.text('Your bills');
      await tester.scrollUntilVisible(yourBills, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(yourBills);
      await tester.pumpAndSettle();
      expect(location(container), '/more/settings/bills');
      expect(find.byType(BillsScreen), findsOneWidget);

      expect(await pressBack(tester), isTrue);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(await pressBack(tester), isTrue);
      expect(find.byType(BillsScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(_tab(tester), 3, reason: 'still on the Bills tab');
      expect(location(container), '/bills');
    });

    testWidgets('Bills bell -> Settings -> Change unlock pattern -> back, back is Bills', (tester) async {
      await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Bills');
      await tester.tap(find.byKey(const Key('bills-reminder-settings')));
      await tester.pumpAndSettle();

      final change = find.text('Change unlock pattern');
      await tester.scrollUntilVisible(change, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(find.byType(SetupLockScreen), findsOneWidget);

      expect(await pressBack(tester), isTrue);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(await pressBack(tester), isTrue);
      expect(find.byType(BillsScreen), findsOneWidget);
      expect(_tab(tester), 3, reason: 'still on the Bills tab');
    });

    testWidgets('"reminders are off" note on Bills opens Settings; back returns to Bills', (tester) async {
      final repo = _repo()
        ..profile = const Profile(
          theme: 'ocean',
          dailyReminderEnabled: true,
          dailyReminderTime: kDefaultDailyReminderTime,
          billRemindersEnabled: false,
          billReminderDaysBefore: kDefaultBillReminderDaysBefore,
        );
      await pumpApp(tester, repo: repo);
      await tapTab(tester, 'Bills');
      await tester.tap(find.byKey(const Key('bills-reminders-off')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(await pressBack(tester), isTrue);
      expect(find.byType(BillsScreen), findsOneWidget);
    });

    testWidgets('More -> Settings -> "Your bills" -> back is Settings; its bills can still be edited',
        (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'More');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final yourBills = find.text('Your bills');
      await tester.scrollUntilVisible(yourBills, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(yourBills);
      await tester.pumpAndSettle();
      expect(find.byType(BillsScreen), findsOneWidget);

      // Edit a bill from here: its form opens over it and closes back to it.
      await tester.tap(find.byKey(const Key('bill-bill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bill-action-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(BillFormScreen), findsOneWidget);
      expect(await pressBack(tester), isTrue);
      expect(find.byType(BillsScreen), findsOneWidget);

      expect(await pressBack(tester), isTrue);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(location(container), '/more/settings');
      expect(_tab(tester), 4);
    });

    testWidgets('Dashboard "N uncategorized" opens Transactions showing only those', (tester) async {
      final repo = _repo()
        ..totals = const MonthTotals(
          expensePaise: 24690,
          lastExpensePaise: 0,
          incomePaise: 0,
          lastIncomePaise: 0,
          uncategorizedCount: 1,
        );
      final (_, container) = await pumpApp(tester, repo: repo);
      // Transactions was left on another month; the card brings it back to this one.
      container.read(selectedMonthProvider.notifier).set(const YearMonth(2026, 7));

      await tester.tap(find.byKey(const Key('dashboard-uncategorized')));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionsScreen), findsOneWidget);
      expect(container.read(selectedMonthProvider), const YearMonth(2026, 9));
      expect(find.text('DMart'), findsOneWidget);
      expect(find.text('Swiggy dinner'), findsNothing);
      expect(find.text('Showing only: Uncategorized'), findsOneWidget);

      // Back goes to the Dashboard (where the card was).
      expect(await pressBack(tester), isTrue);
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });

  group('while locked', () {
    testWidgets('back does not touch the screen underneath (an Edit with unsaved changes)', (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Transactions');
      await tester.tap(find.text('Swiggy dinner'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry-description')), 'Swiggy dinner with family');
      await tester.pump();

      container.read(lockControllerProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);

      for (var i = 0; i < 2; i++) {
        expect(await pressBack(tester), isTrue, reason: 'swallowed, not passed on to Android');
        expect(_discardDialog, findsNothing, reason: 'the router never saw the back press');
        expect(location(container), '/transactions/t1');
        expect(find.byType(LockScreen), findsOneWidget);
      }

      container.read(lockControllerProvider.notifier).unlock();
      await tester.pumpAndSettle();
      expect(find.byType(EditTransactionScreen), findsOneWidget);
      expect(find.text('Swiggy dinner with family'), findsOneWidget, reason: 'the typed text survived');
    });

    testWidgets('back closes the lock screen\'s own dialog, and only that', (tester) async {
      final (_, container) = await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Transactions');
      await tester.tap(find.text('Swiggy dinner'));
      await tester.pumpAndSettle();

      container.read(lockControllerProvider.notifier).lock();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot pattern?'));
      await tester.pumpAndSettle();
      expect(find.text('Forgot your pattern?'), findsOneWidget);

      expect(await pressBack(tester), isTrue);
      expect(find.text('Forgot your pattern?'), findsNothing);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(location(container), '/transactions/t1');
    });
  });

  group('unsaved changes', () {
    testWidgets('Edit transaction: untouched closes at once; changed asks first (system back and app bar)',
        (tester) async {
      final (repo, container) = await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Transactions');

      // Untouched: no question.
      await tester.tap(find.text('Swiggy dinner'));
      await tester.pumpAndSettle();
      await pressBack(tester);
      expect(_discardDialog, findsNothing);
      expect(find.byType(EditTransactionScreen), findsNothing);

      // Changed: asks, and "Keep editing" keeps everything.
      await tester.tap(find.text('Swiggy dinner'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry-description')), 'Swiggy lunch');
      await tester.pump();
      await pressBack(tester);
      expect(_discardDialog, findsOneWidget);
      expect(find.text("What you typed hasn't been saved."), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(EditTransactionScreen), findsOneWidget);
      expect(find.text('Swiggy lunch'), findsOneWidget);

      // The app bar's back arrow asks too; Discard leaves.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(location(container), '/transactions');
      expect(repo.txnUpdates, isEmpty);
    });

    testWidgets('Edit transaction: saving closes without asking', (tester) async {
      final (repo, _) = await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Transactions');
      await tester.tap(find.text('Swiggy dinner'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry-description')), 'Swiggy lunch');
      await tester.pump();
      final save = find.byKey(const Key('entry-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(_discardDialog, findsNothing);
      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(repo.txnUpdates.single.draft.description, 'Swiggy lunch');
    });

    testWidgets('Bill form (new): untouched closes; typed asks; Discard leaves', (tester) async {
      final (repo, _) = await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Bills');

      await tester.tap(find.byKey(const Key('add-bill')));
      await tester.pumpAndSettle();
      await pressBack(tester);
      expect(_discardDialog, findsNothing);
      expect(find.byType(BillFormScreen), findsNothing);

      await tester.tap(find.byKey(const Key('add-bill')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bill-name')), 'Water');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Water'), findsOneWidget);

      await pressBack(tester);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(BillFormScreen), findsNothing);
      expect(repo.billInserts, isEmpty);
    });

    testWidgets('Bill form (edit): untouched closes; a changed amount asks', (tester) async {
      await pumpApp(tester, repo: _repo());
      await tapTab(tester, 'Bills');
      Future<void> openEdit() async {
        await tester.tap(find.byKey(const Key('bill-bill-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('bill-action-edit')));
        await tester.pumpAndSettle();
      }

      await openEdit();
      expect(find.text('Edit bill'), findsOneWidget);
      await pressBack(tester);
      expect(_discardDialog, findsNothing, reason: 'filled in from the bill, nothing changed');
      expect(find.byType(BillFormScreen), findsNothing);

      await openEdit();
      await tester.enterText(find.byKey(const Key('bill-amount')), '1500');
      await tester.pump();
      await pressBack(tester);
      expect(_discardDialog, findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(BillFormScreen), findsNothing);
    });
  });
}
