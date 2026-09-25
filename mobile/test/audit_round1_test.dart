import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/theme.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/features/accounts/accounts_screen.dart';
import 'package:ventrafin/features/auth/login_screen.dart';
import 'package:ventrafin/features/categories/categories_screen.dart';
import 'package:ventrafin/features/entry/add_screen.dart';
import 'package:ventrafin/features/lock/lock_controller.dart';
import 'package:ventrafin/features/lock/lock_screen.dart';
import 'package:ventrafin/features/lock/pattern_pad.dart';
import 'package:ventrafin/features/lock/setup_lock_screen.dart';
import 'package:ventrafin/features/reports/reports_screen.dart';
import 'package:ventrafin/features/shell/simple_screens.dart';

import 'support/app_harness.dart';
import 'support/fake_repository.dart';

Finder get _discardDialog => find.text('Discard changes?');

/// A sheet's drag handle, dragged most of the way down the screen.
Future<void> _dragSheetDown(WidgetTester tester) async {
  final sheet = find.byType(BottomSheet);
  final handle = tester.getTopLeft(sheet) + Offset(tester.getSize(sheet).width / 2, 10);
  await tester.dragFrom(handle, const Offset(0, 700));
  await tester.pumpAndSettle();
}

/// Opens [child] as a pushed page over a plain first page, so back has
/// somewhere to go.
Widget _pushed(Widget child) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => child)),
            child: const Text('open'),
          ),
        ),
      ),
    );

/// Unlocks without a real pattern check, so the Change pattern screen can
/// be driven with drawn patterns.
class _FakeLock extends LockController {
  @override
  bool build() => false;

  @override
  Future<UnlockResult> confirmCurrentPattern(List<int> dots) async => const Unlocked();
}

Future<void> _draw(WidgetTester tester, List<int> dots) async {
  final pad = find.byType(PatternPad);
  final origin = tester.getTopLeft(pad);
  final cell = tester.getSize(pad).width / 3;
  Offset at(int i) => origin + Offset((i % 3 + 0.5) * cell, (i ~/ 3 + 0.5) * cell);
  final gesture = await tester.startGesture(at(dots.first));
  for (final d in dots.skip(1)) {
    await gesture.moveTo(Offset.lerp(at(dots.first), at(d), 0.5)!);
    await gesture.moveTo(at(d));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('unsaved changes in sheets', () {
    testWidgets('category sheet: untouched closes on a tap outside, without asking', (tester) async {
      await pumpWithFakes(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('category-cat-food')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsNothing);
      expect(find.byKey(const Key('category-name')), findsNothing);
    });

    testWidgets('category sheet with a change: tap outside, drag down, back and Cancel all ask', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('category-cat-food')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('category-name')), 'Khana');
      await tester.pumpAndSettle();
      final nameTop = tester.getTopLeft(find.byKey(const Key('category-name')));

      Future<void> keepEditing() async {
        expect(_discardDialog, findsOneWidget);
        expect(find.text("What you typed hasn't been saved."), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('category-name')), findsOneWidget);
        expect(tester.getTopLeft(find.byKey(const Key('category-name'))), nameTop, reason: 'sheet fully open again');
        expect(find.text('Khana'), findsOneWidget);
      }

      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      await keepEditing();

      await _dragSheetDown(tester);
      await keepEditing();

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      await keepEditing();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category-name')), findsNothing);
      expect(repo.categoryUpdates, isEmpty);
    });

    testWidgets('category sheet: saving closes without asking', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('category-cat-food')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('category-name')), 'Khana');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category-save')));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsNothing);
      expect(repo.categoryUpdates.single.name, 'Khana');
    });

    testWidgets('new category: a typed name asks before being thrown away', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('add-category-expense')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsNothing, reason: 'nothing typed');

      await tester.tap(find.byKey(const Key('add-category-expense')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-category-name')), 'Pet care');
      await tester.pumpAndSettle();
      await _dragSheetDown(tester);
      expect(_discardDialog, findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-category-name')), findsNothing);
      expect(repo.categoryInserts, isEmpty);
    });

    testWidgets('account sheets: new and edit ask only when changed', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const AccountsScreen());
      await tester.tap(find.byKey(const Key('add-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('account-name')), 'HDFC');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-name')), findsNothing);

      await tester.tap(find.byKey(const Key('account-acc-bank')));
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(_discardDialog, findsNothing, reason: 'untouched');
      expect(find.byKey(const Key('account-name')), findsNothing);

      await tester.tap(find.byKey(const Key('account-acc-bank')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const Key('account-type')), matching: find.text('Cash')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsOneWidget, reason: 'the type was changed');
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(repo.accountUpdates, isEmpty);
      expect(repo.accountInserts, isEmpty);
    });

    testWidgets('Change pattern: asks once a new pattern has been drawn', (tester) async {
      final overrides = <Override>[
        lockControllerProvider.overrideWith(_FakeLock.new),
        biometricsAvailableProvider.overrideWith((ref) async => false),
        currentUserProvider.overrideWithValue(null),
      ];
      await pumpWithFakes(tester, _pushed(const SetupLockScreen(requireCurrent: true)), overrides: overrides);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Only the current pattern drawn: nothing new to lose.
      await _draw(tester, [0, 1, 2, 5]);
      expect(find.text('Draw a new unlock pattern'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_discardDialog, findsNothing);
      expect(find.byType(SetupLockScreen), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _draw(tester, [0, 1, 2, 5]);
      await _draw(tester, [6, 7, 8, 5]); // the new pattern, first time
      expect(find.text('Draw the pattern again to confirm'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(_discardDialog, findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Draw the pattern again to confirm'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(SetupLockScreen), findsNothing);
    });
  });

  group('load errors offer Retry', () {
    testWidgets('Dashboard: totals error with Retry', (tester) async {
      final repo = FakeRepository()..failNextMonthTotalsWith = const SocketException('offline');
      await pumpWithFakes(tester, const DashboardScreen(), repo: repo);
      expect(find.text("Couldn't reach the server. Check your internet connection and try again."), findsOneWidget);
      expect(find.text('Spent'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Spent'), findsOneWidget);
    });

    testWidgets('Dashboard: the category breakdown has its own Retry', (tester) async {
      final repo = FakeRepository()..failNextComparisonWith = const SocketException('offline');
      await pumpWithFakes(tester, const DashboardScreen(), repo: repo);
      expect(find.text('Spent'), findsOneWidget, reason: 'the totals still show');
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Nothing spent yet in September 2026.'), findsOneWidget);
    });

    testWidgets('Add: accounts that failed to load say why, with Retry', (tester) async {
      final repo = FakeRepository()..failNextFetchAccountsWith = const SocketException('offline');
      await pumpWithFakes(tester, const AddScreen(), repo: repo);
      expect(
        find.text("Couldn't load your accounts. Couldn't reach the server. Check your internet connection and try again."),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      final account = tester.widget<DropdownButton<String>>(
          find.descendant(of: find.byKey(const Key('entry-account')), matching: find.byType(DropdownButton<String>)));
      expect(account.value, 'acc-cash', reason: 'filled in once the accounts arrive');
    });

    testWidgets('Dashboard: pull down to refresh', (tester) async {
      final repo = FakeRepository()..failNextMonthTotalsWith = const SocketException('offline');
      await pumpWithFakes(tester, const DashboardScreen(), repo: repo);
      expect(find.text('Retry'), findsOneWidget);
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Spent'), findsOneWidget);
    });

    testWidgets('Reports: a section that failed has its own Retry', (tester) async {
      final repo = FakeRepository()..failNextMonthTotalsWith = const SocketException('offline');
      await pumpWithFakes(tester, const ReportsScreen(), repo: repo, overrides: [currentUserProvider.overrideWithValue(null)]);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text("Couldn't reach the server. Check your internet connection and try again."), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('status bar icons (verify on a device too)', () {
    testWidgets('sign-in screen asks for dark icons on a transparent bar', (tester) async {
      await pumpWithFakes(tester, const LoginScreen());
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
      expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    });

    testWidgets('the lock screen asks for dark icons', (tester) async {
      // Leave an app-bar screen showing first, so its light icons would linger.
      await pumpApp(tester, repo: FakeRepository(), unlocked: false);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    });

    testWidgets('screens with an app bar keep icons that suit the brand colour', (tester) async {
      for (final (theme, expected) in [('ocean', Brightness.light), ('sunflower', Brightness.dark)]) {
        await pumpWithFakes(
          tester,
          Scaffold(appBar: AppBar(title: const Text('Bills'))),
          theme: buildAppTheme(themeTokensFor(theme)),
        );
        expect(SystemChrome.latestStyle?.statusBarIconBrightness, expected, reason: theme);
      }
    });
  });
}
