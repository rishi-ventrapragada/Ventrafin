import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';

/// "Overdue · 5 days", "Due today", "Due in 3 days", "Due 10 Oct". Same
/// wording as the web's Bills page (web/src/lib/bills.ts).
String billStatusLabel(Bill b) => switch (b.status) {
  BillStatus.overdue =>
    b.overdueCount > 1
        ? 'Overdue · ${b.overdueCount} months'
        : 'Overdue · ${-b.daysUntil} ${-b.daysUntil == 1 ? 'day' : 'days'}',
  BillStatus.dueToday => 'Due today',
  BillStatus.dueSoon => b.daysUntil == 1 ? 'Due tomorrow' : 'Due in ${b.daysUntil} days',
  BillStatus.upcoming => 'Due ${DateFormat('d MMM').format(b.nextDueDate)}',
};

/// Red for overdue, amber for due within a week, grey otherwise. Text
/// colours reach 4.5:1 on their tint.
({Color fg, Color bg, IconData icon}) billStatusLook(BillStatus s) => switch (s) {
  BillStatus.overdue => (fg: const Color(0xFFB71C1C), bg: const Color(0xFFFDECEA), icon: Icons.error),
  BillStatus.dueToday ||
  BillStatus.dueSoon => (fg: kUncategorizedInkColor, bg: const Color(0xFFFFF3D6), icon: Icons.schedule),
  BillStatus.upcoming => (fg: const Color(0xFF455A64), bg: const Color(0xFFEFF2F4), icon: Icons.event),
};

class BillStatusChip extends StatelessWidget {
  const BillStatusChip({super.key, required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final look = billStatusLook(bill.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(look.icon, size: 14, color: look.fg),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              billStatusLabel(bill),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: look.fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bill's category icon, or a receipt / EMI icon when it has none.
class BillAvatar extends StatelessWidget {
  const BillAvatar({super.key, required this.bill, required this.category, this.size = 34});

  final Bill bill;
  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = category;
    if (c != null) return CategoryAvatar(category: c, size: size);
    return OutlinedIconCircle(
      icon: bill.kind == BillKind.emi ? Icons.event_repeat : Icons.receipt_long,
      color: kTransferColor,
      size: size,
      semanticLabel: bill.kind.label,
    );
  }
}

/// A sensible "paid by" for a payment from [type] of account.
PaymentMethod defaultMethodFor(AccountType? type) => switch (type) {
  AccountType.cash => PaymentMethod.cash,
  AccountType.credit => PaymentMethod.card,
  _ => PaymentMethod.upi,
};
