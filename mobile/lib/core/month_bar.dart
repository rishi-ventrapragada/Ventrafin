import 'package:flutter/material.dart';

import 'india_time.dart';

/// ‹ September 2026 › for an app bar's bottom, with a month picker on the
/// label. Drawn in the app bar's foreground colour, so it reads on every
/// theme's brand colour (dark on the yellow themes).
class MonthBar extends StatelessWidget {
  const MonthBar({super.key, required this.month, required this.onChanged, required this.canGoForward});

  final YearMonth month;
  final ValueChanged<YearMonth> onChanged;
  final bool canGoForward;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<YearMonth>(
      context: context,
      builder: (context) => MonthPickerDialog(initial: month),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          color: fg,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(month.previous),
        ),
        Expanded(
          child: TextButton.icon(
            key: const Key('month-picker'),
            style: TextButton.styleFrom(foregroundColor: fg),
            onPressed: () => _pick(context),
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text(month.label, style: const TextStyle(fontSize: 16)),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          color: fg,
          disabledColor: fg.withValues(alpha: 0.3),
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoForward ? () => onChanged(month.next) : null,
        ),
      ],
    );
  }
}

class MonthPickerDialog extends StatefulWidget {
  const MonthPickerDialog({super.key, required this.initial});

  final YearMonth initial;

  @override
  State<MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<MonthPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return AlertDialog(
      title: Row(
        children: [
          IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('$_year', textAlign: TextAlign.center)),
          IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
        ],
      ),
      content: SizedBox(
        width: 280,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          childAspectRatio: 1.6,
          children: [
            for (var m = 1; m <= 12; m++)
              TextButton(
                style: widget.initial == YearMonth(_year, m)
                    ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                    : null,
                onPressed: () => Navigator.pop(context, YearMonth(_year, m)),
                child: Text(names[m - 1]),
              ),
          ],
        ),
      ),
    );
  }
}
