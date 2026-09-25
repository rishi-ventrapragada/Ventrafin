// Phase 7: CSV export on the phone. Date presets (same as the web app),
// file names, and the sheet that fetches the CSV from Postgres and hands it
// to the share sheet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/features/settings/export_range.dart';
import 'package:ventrafin/features/settings/export_sheet.dart';

import 'support/fake_repository.dart';

void main() {
  group('export ranges (same as web/src/lib/exportRange.ts)', () {
    test('Indian financial year: April to March', () {
      expect(financialYearStart(DateTime(2026, 9, 25)), DateTime(2026, 4, 1));
      expect(financialYearStart(DateTime(2026, 4, 1)), DateTime(2026, 4, 1));
      expect(financialYearStart(DateTime(2026, 3, 31)), DateTime(2025, 4, 1));
      expect(financialYearLabel(DateTime(2026, 4, 1)), 'FY 2026-27');
      expect(financialYearLabel(DateTime(2099, 4, 1)), 'FY 2099-00');
    });

    test('presets from today', () {
      final today = DateTime(2026, 9, 25);
      expect(presetRange(RangePreset.thisMonth, today), DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
      expect(presetRange(RangePreset.lastMonth, today), DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)));
      expect(presetRange(RangePreset.thisFy, today), DateRange(DateTime(2026, 4, 1), DateTime(2027, 3, 31)));
      expect(presetRange(RangePreset.lastFy, today), DateRange(DateTime(2025, 4, 1), DateTime(2026, 3, 31)));
      expect(presetRange(RangePreset.all, today), const DateRange(null, null));
      expect(presetRange(RangePreset.custom, today), isNull);
      expect(presetRange(RangePreset.lastMonth, DateTime(2026, 1, 10)), DateRange(DateTime(2025, 12, 1), DateTime(2025, 12, 31)));
      expect(presetRange(RangePreset.thisMonth, DateTime(2028, 2, 10)), DateRange(DateTime(2028, 2, 1), DateTime(2028, 2, 29)));
    });

    test('labels and file names match the web', () {
      expect(rangeLabel(DateRange(DateTime(2026, 4, 1), DateTime(2027, 3, 31))), '01/04/2026 to 31/03/2027');
      expect(rangeLabel(const DateRange(null, null)), 'All dates');
      expect(rangeLabel(DateRange(null, DateTime(2026, 9, 25))), 'Up to 25/09/2026');
      final today = DateTime(2026, 9, 25);
      expect(exportFileName(DateRange(DateTime(2026, 4, 1), DateTime(2027, 3, 31)), today),
          'ventrafin-transactions-2026-04-01-to-2027-03-31.csv');
      expect(exportFileName(const DateRange(null, null), today), 'ventrafin-transactions-all-2026-09-25.csv');
      expect(exportFileName(DateRange(null, DateTime(2026, 1, 31)), today), 'ventrafin-transactions-start-to-2026-01-31.csv');
    });

    test('counts data rows; a quoted line break is part of a cell', () {
      const heading = 'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n';
      expect(csvRowCount(heading), 0);
      expect(csvRowCount('${heading}2026-09-20,Tea,20.00,Expense,Food,Cash,,UPI\r\n'), 1);
      expect(csvRowCount('${heading}2026-09-20,"Line1\nLine2",1.00,Expense,Food,Bank,,Cash\r\n'
          '2026-09-21,"say ""hi""",2.00,Expense,Food,Bank,,Cash\r\n'), 2);
      expect(csvRowCount(''), 0);
    });
  });

  group('export sheet', () {
    Future<(FakeRepository, List<({String fileName, String csv})>)> pumpSheet(WidgetTester tester) async {
      final shared = <({String fileName, String csv})>[];
      final (repo, _) = await pumpWithFakes(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final n = await showExportSheet(context);
                  if (n != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported $n')));
                  }
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
        surfaceSize: const Size(412, 1400),
        overrides: <Override>[
          csvSharerProvider.overrideWithValue(({required String fileName, required String csv}) async {
            shared.add((fileName: fileName, csv: csv));
          }),
        ],
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return (repo, shared);
    }

    testWidgets('this month by default; shares the file Postgres made, named by its dates', (tester) async {
      final (repo, shared) = await pumpSheet(tester);
      expect(find.text('01/09/2026 to 30/09/2026'), findsOneWidget);
      expect(find.text('FY 2026-27: 01/04/2026 to 31/03/2027'), findsOneWidget);

      await tester.tap(find.byKey(const Key('export-share')));
      await tester.pumpAndSettle();
      expect(repo.exportCalls.single.from, DateTime(2026, 9, 1));
      expect(repo.exportCalls.single.to, DateTime(2026, 9, 30));
      expect(shared.single.fileName, 'ventrafin-transactions-2026-09-01-to-2026-09-30.csv');
      expect(shared.single.csv, repo.exportCsv);
      expect(find.text('Exported 1'), findsOneWidget);
    });

    testWidgets('financial year and all time', (tester) async {
      final (repo, shared) = await pumpSheet(tester);
      await tester.tap(find.byKey(const Key('export-thisFy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-share')));
      await tester.pumpAndSettle();
      expect(repo.exportCalls.last.from, DateTime(2026, 4, 1));
      expect(repo.exportCalls.last.to, DateTime(2027, 3, 31));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-share')));
      await tester.pumpAndSettle();
      expect(repo.exportCalls.last.from, isNull);
      expect(repo.exportCalls.last.to, isNull);
      expect(shared.last.fileName, 'ventrafin-transactions-all-2026-09-25.csv');
    });

    testWidgets('nothing in range: says so and shares nothing', (tester) async {
      final (repo, shared) = await pumpSheet(tester);
      repo.exportCsv = 'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n';
      await tester.tap(find.byKey(const Key('export-share')));
      await tester.pumpAndSettle();
      expect(find.textContaining('no transactions in that range'), findsOneWidget);
      expect(shared, isEmpty);
    });

    testWidgets('fits a 360 dp phone at text ×1.3', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpWithFakes(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showExportSheet(context), child: const Text('Open')),
          ),
        ),
        surfaceSize: const Size(360, 700),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-share')), findsOneWidget);
    });

    testWidgets('a failed request explains why and keeps the sheet open', (tester) async {
      final (repo, shared) = await pumpSheet(tester);
      repo.failNextExportWith = Exception('SocketException: Failed host lookup');
      await tester.tap(find.byKey(const Key('export-share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-error')), findsOneWidget);
      expect(find.byKey(const Key('export-share')), findsOneWidget);
      expect(shared, isEmpty);
    });
  });
}
