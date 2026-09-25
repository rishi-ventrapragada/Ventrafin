import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../data/providers.dart';
import 'export_range.dart';

/// Hands a finished CSV to Android's share sheet (email, Drive, WhatsApp…).
typedef CsvSharer = Future<void> Function({required String fileName, required String csv});

/// Replaced in widget tests, so no share sheet opens.
final csvSharerProvider = Provider<CsvSharer>((ref) => shareCsvFile);

/// Excel only reads a CSV as UTF-8 (₹, Hindi text) when it starts with a
/// byte-order mark. share_plus writes the bytes to a file in the app's
/// private cache, which Android clears when it needs space.
Future<void> shareCsvFile({required String fileName, required String csv}) async {
  final bytes = Uint8List.fromList(utf8.encode('﻿$csv'));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'text/csv', name: fileName)],
      fileNameOverrides: [fileName],
      subject: fileName,
      title: 'Ventrafin transactions',
    ),
  );
}

/// Settings › Export: pick the dates, then share the CSV. Returns how many
/// transactions were shared, or null when closed without sharing.
Future<int?> showExportSheet(BuildContext context) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const ExportSheet(),
    );

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  RangePreset _preset = RangePreset.thisMonth;
  DateTimeRange? _custom;
  bool _busy = false;
  String? _error;

  DateTime get _today => indiaToday(ref.read(clockProvider));

  DateRange? get _range => _preset == RangePreset.custom
      ? (_custom == null ? null : DateRange(_custom!.start, _custom!.end))
      : presetRange(_preset, _today);

  String _detail(RangePreset p) {
    final today = _today;
    switch (p) {
      case RangePreset.thisFy:
        return '${financialYearLabel(financialYearStart(today))}: ${rangeLabel(presetRange(p, today)!)}';
      case RangePreset.lastFy:
        final start = DateTime(financialYearStart(today).year - 1, 4, 1);
        return '${financialYearLabel(start)}: ${rangeLabel(presetRange(p, today)!)}';
      case RangePreset.custom:
        return _custom == null ? 'Any start and end date' : rangeLabel(DateRange(_custom!.start, _custom!.end));
      default:
        return rangeLabel(presetRange(p, today)!);
    }
  }

  Future<void> _pickDates() async {
    final today = _today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: DateTime(2099, 12, 31),
      initialDateRange: _custom ?? DateTimeRange(start: YearMonth.of(today).firstDay, end: today),
      helpText: 'Dates to export',
      saveText: 'Done',
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _preset = RangePreset.custom;
      });
    }
  }

  Future<void> _share() async {
    final range = _range;
    if (range == null) {
      setState(() => _error = 'Choose the dates first.');
      return;
    }
    if (!ref.read(isOnlineProvider)) {
      setState(() => _error = "There's no internet connection.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final csv = await ref.read(repositoryProvider).exportTransactionsCsv(from: range.from, to: range.to);
      final count = csvRowCount(csv);
      if (count == 0) {
        setState(() => _error = 'There are no transactions in that range, so there is nothing to share.');
        return;
      }
      await ref.read(csvSharerProvider)(fileName: exportFileName(range, _today), csv: csv);
      if (mounted) Navigator.of(context).pop(count);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text('Export transactions (CSV)', style: theme.textTheme.titleMedium),
              subtitle: const Text(
                'A file that opens in Excel: date, description, amount (₹), type, category, account, '
                'to account, paid by. Share it to email, Drive or WhatsApp. The web app makes the same file.',
              ),
            ),
            const Divider(height: 1),
            RadioGroup<RangePreset>(
              groupValue: _preset,
              onChanged: (p) {
                if (p == null || _busy) return;
                if (p == RangePreset.custom) {
                  _pickDates();
                } else {
                  setState(() {
                    _preset = p;
                    _error = null;
                  });
                }
              },
              child: Column(
                children: [
                  for (final p in RangePreset.values)
                    RadioListTile<RangePreset>(
                      key: Key('export-${p.name}'),
                      value: p,
                      dense: true,
                      title: Text(p.label),
                      subtitle: Text(_detail(p)),
                      secondary: p == RangePreset.custom
                          ? IconButton(
                              tooltip: 'Choose dates',
                              icon: const Icon(Icons.date_range),
                              onPressed: _busy ? null : _pickDates,
                            )
                          : null,
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(_error!, key: const Key('export-error'), style: TextStyle(color: theme.colorScheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FilledButton.icon(
                key: const Key('export-share'),
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share),
                label: const Text('Share CSV file'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
