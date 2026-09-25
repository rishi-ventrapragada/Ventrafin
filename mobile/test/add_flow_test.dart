import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/features/entry/add_screen.dart';

import 'support/fake_repository.dart';

Future<(FakeRepository, SharedPreferences)> pumpAddScreen(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool online = true,
}) =>
    pumpWithFakes(tester, const AddScreen(), prefs: prefs, online: online);

Future<void> typeAmount(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(Key('keypad-${k == '<' ? 'back' : k}')));
    await tester.pump();
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String amountText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('entry-amount-text'))).data!;

bool chipSelected(WidgetTester tester, String method) =>
    tester.widget<ChoiceChip>(find.byKey(Key('method-$method'))).selected;

void main() {
  testWidgets('batch entry: keypad amount, Save & add another keeps context and confirms what was saved',
      (tester) async {
    final (repo, prefs) = await pumpAddScreen(tester);

    // Keypad is shown first; the amount starts at 0.
    expect(find.byKey(const Key('keypad-1')), findsOneWidget);
    expect(amountText(tester), '0');

    // Date defaults to today *in India* (00:30 IST on the 25th).
    expect(find.text('Today, 25 Sep'), findsOneWidget);

    // Entry 1: ₹1,250 Swiggy dinner, UPI.
    await typeAmount(tester, '1250');
    expect(amountText(tester), '1,250');
    await tester.tap(find.byKey(const Key('keypad-done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-description')), 'Swiggy dinner');
    await tapVisible(tester, find.byKey(const Key('method-upi')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(repo.inserted, hasLength(1));
    final first = repo.inserted.single.draft;
    expect(first.amountPaise, 125000);
    expect(first.description, 'Swiggy dinner');
    expect(first.type, TxnType.expense);
    expect(first.accountId, 'acc-cash', reason: 'defaults to the Cash account');
    expect(first.paymentMethod, PaymentMethod.upi);
    expect(toIsoDate(first.date), '2026-09-25');
    expect(first.categoryId, isNull, reason: 'left on Auto so the database categorizes it');

    // Clear confirmation, including the category the database picked.
    expect(find.byKey(const Key('just-saved')), findsOneWidget);
    expect(find.textContaining('1 saved this session'), findsOneWidget);
    expect(find.textContaining('₹1,250.00 · Swiggy dinner · Food (auto) · Cash/UPI'), findsOneWidget);

    // Stays on the screen, ready for the next one: amount and description
    // cleared, keypad back, account / method / date kept.
    expect(amountText(tester), '0');
    expect(find.byKey(const Key('keypad-1')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('entry-description'))).controller!.text, isEmpty);
    expect(chipSelected(tester, 'upi'), isTrue);
    expect(find.text('Today, 25 Sep'), findsOneWidget);

    // Entry 2: ₹99.50 chai. No need to pick the method again.
    await typeAmount(tester, '99.5');
    expect(amountText(tester), '99.5');
    await tester.tap(find.byKey(const Key('keypad-done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-description')), 'Chai');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(repo.inserted, hasLength(2));
    final second = repo.inserted[1].draft;
    expect(second.amountPaise, 9950);
    expect(second.paymentMethod, PaymentMethod.upi);
    expect(second.accountId, 'acc-cash');
    expect(repo.inserted[0].id, isNot(repo.inserted[1].id), reason: 'each entry gets its own id');
    expect(find.textContaining('2 saved this session · ₹1,349.50 spent'), findsOneWidget);
    expect(find.textContaining('Uncategorized'), findsOneWidget, reason: '"Chai" matched nothing');

    // Last-used account and method are remembered for next time.
    expect(prefs.getString('entry.lastAccountId'), 'acc-cash');
    expect(prefs.getString('entry.lastPaymentMethod'), 'upi');
  });

  testWidgets('validation: amount is required, and payment method is required for expenses', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);

    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(find.text('Choose how you paid'), findsOneWidget);
    expect(repo.attemptedIds, isEmpty);

    await typeAmount(tester, '100');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(find.text('Enter an amount'), findsNothing);
    expect(find.text('Choose how you paid'), findsOneWidget);
    expect(repo.attemptedIds, isEmpty, reason: 'nothing is sent while the form is invalid');

    await tapVisible(tester, find.byKey(const Key('method-cash')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(repo.inserted, hasLength(1));
    expect(repo.inserted.single.draft.amountPaise, 10000);
  });

  testWidgets('income does not require a payment method', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);
    await tapVisible(tester, find.text('Income'));
    await typeAmount(tester, '50000');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(repo.inserted, hasLength(1));
    expect(repo.inserted.single.draft.type, TxnType.income);
    expect(repo.inserted.single.draft.paymentMethod, isNull);
  });

  testWidgets('transfer: needs a different destination account and never sends a category', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);

    await tapVisible(tester, find.text('Transfer'));
    expect(find.byKey(const Key('entry-to-account')), findsOneWidget);
    expect(find.byKey(const Key('entry-category')), findsNothing);

    await typeAmount(tester, '2000');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(find.text('Choose the account the money went to'), findsOneWidget);
    expect(repo.attemptedIds, isEmpty);

    await tapVisible(tester, find.byKey(const Key('entry-to-account')));
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(repo.inserted, hasLength(1));
    final d = repo.inserted.single.draft;
    expect(d.type, TxnType.transfer);
    expect(d.accountId, 'acc-cash');
    expect(d.toAccountId, 'acc-bank');
    expect(d.toRow()['category_id'], isNull);
  });

  testWidgets('a failed save is reported, keeps the form, and the retry reuses the same id', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);
    repo.failNextInsertWith = const SocketException('Network is unreachable');

    await typeAmount(tester, '250');
    await tester.tap(find.byKey(const Key('keypad-done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-description')), 'DMart');
    await tapVisible(tester, find.byKey(const Key('method-card')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    // Never silent: a dialog explains it wasn't saved.
    expect(find.text('Not saved'), findsOneWidget);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(repo.inserted, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Nothing lost.
    expect(amountText(tester), '250');
    expect(tester.widget<TextField>(find.byKey(const Key('entry-description'))).controller!.text, 'DMart');
    expect(chipSelected(tester, 'card'), isTrue);

    // Retry succeeds with the same client-generated id (no duplicate possible).
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(repo.inserted, hasLength(1));
    expect(repo.attemptedIds, hasLength(2));
    expect(repo.attemptedIds[0], repo.attemptedIds[1]);
  });

  testWidgets('offline: save is refused with a clear message', (tester) async {
    final (repo, _) = await pumpAddScreen(tester, online: false);
    await typeAmount(tester, '75');
    await tapVisible(tester, find.byKey(const Key('method-cash')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(find.text('Not saved'), findsOneWidget);
    expect(find.textContaining("no internet connection"), findsOneWidget);
    expect(repo.attemptedIds, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(amountText(tester), '75');
  });

  testWidgets('remembers the last-used account and payment method', (tester) async {
    await pumpAddScreen(tester, prefs: {
      'entry.lastAccountId': 'acc-bank',
      'entry.lastPaymentMethod': 'card',
    });
    expect(
      tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('entry-account'))).initialValue,
      'acc-bank',
    );
    expect(find.text('Bank'), findsOneWidget);
    expect(chipSelected(tester, 'card'), isTrue);
  });

  // The test font draws every glyph as a full square, so labels are wider
  // here than on a phone: 412 and 360 dp exercise the stacked layout, 640 dp
  // the side-by-side one.
  for (final (width, scale) in [(412.0, 1.0), (360.0, 1.0), (412.0, 1.3), (360.0, 1.3), (640.0, 1.0)]) {
    testWidgets('save buttons keep their labels on one line (${width.toInt()} dp wide, text ×$scale)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpWithFakes(tester, const AddScreen(), surfaceSize: Size(width, 915));

      for (final label in ['Save & close', 'Save & add another']) {
        final finder = find.text(label);
        await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final oneLine = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout();
        expect(paragraph.size.height, closeTo(oneLine.height, 0.5), reason: '"$label" wrapped onto more than one line');
        expect(paragraph.size.width, greaterThanOrEqualTo(oneLine.width - 0.5), reason: '"$label" was cut off');
        oneLine.dispose();
      }

      final closeTop = tester.getTopLeft(find.byKey(const Key('entry-save-close'))).dy;
      final anotherTop = tester.getTopLeft(find.byKey(const Key('entry-save-another'))).dy;
      if (width >= 640) {
        expect(closeTop, anotherTop, reason: 'room for both: side by side');
      } else {
        expect(closeTop, greaterThan(anotherTop), reason: 'too narrow: stacked, primary action first');
      }
    });
  }

  testWidgets('keypad: backspace, decimals and grouping', (tester) async {
    await pumpAddScreen(tester);
    await typeAmount(tester, '1234567');
    expect(amountText(tester), '12,34,567');
    await typeAmount(tester, '<<');
    expect(amountText(tester), '12,345');
    await typeAmount(tester, '.999');
    expect(amountText(tester), '12,345.99', reason: 'a third decimal is ignored');
  });
}
