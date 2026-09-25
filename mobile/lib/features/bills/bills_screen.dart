import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/offline_banner.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../reminders/reminder_plan.dart';
import 'bill_visuals.dart';

/// Settings, pushed over the tabs from Bills (the bell, "reminders are
/// switched off"), so back returns to Bills.
const String kBillsSettingsRoute = '/bills/settings';

/// Recurring bills and EMIs, soonest due first, with overdue ones in red.
/// Due dates and status come from Postgres (`get_bill_schedule`), the same
/// as on the web. Tap a bill to mark it paid, edit or delete it.
class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(billsProvider);
    final profile = ref.watch(effectiveProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
        actions: [
          IconButton(
            key: const Key('bills-reminder-settings'),
            tooltip: 'Reminder settings',
            icon: const Icon(Icons.notifications_outlined),
            // Pushed over the tabs, so back returns to Bills.
            onPressed: () => context.push(kBillsSettingsRoute),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-bill'),
        onPressed: () => context.push('/bills/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add bill'),
      ),
      body: switch (async) {
        AsyncValue(:final value?) =>
          value.isEmpty
              ? const _Empty()
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.read(revisionsProvider.notifier).bump(['recurring_bills']);
                    await ref.read(billsProvider.future);
                  },
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      _Summary(bills: value),
                      if (profile != null && !profile.billRemindersEnabled)
                        _Note(
                          key: const Key('bills-reminders-off'),
                          icon: Icons.notifications_off_outlined,
                          text: 'Bill reminders are switched off in Settings. Bills still show here.',
                          onTap: () => context.push(kBillsSettingsRoute),
                        ),
                      for (final b in value) _BillRow(bill: b),
                    ],
                  ),
                ),
        AsyncValue(:final error?) => LoadError(
          message: describeError(error),
          onRetry: () => ref.invalidate(billsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.bills});

  final List<Bill> bills;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = bills.where((b) => b.status == BillStatus.overdue).toList();
    final soon = bills.where((b) => b.status == BillStatus.dueToday || b.status == BillStatus.dueSoon).toList();
    final monthly = bills.fold<int>(0, (s, b) => s + b.amountPaise);
    Widget cell(String label, String value, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    int sum(List<Bill> l) => l.fold(0, (s, b) => s + b.amountPaise);
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            cell(
              'Overdue',
              overdue.isEmpty ? 'None' : '${overdue.length} · ${formatRupeesCompact(sum(overdue))}',
              color: overdue.isEmpty ? null : billStatusLook(BillStatus.overdue).fg,
            ),
            cell(
              'Due in 7 days',
              soon.isEmpty ? 'None' : '${soon.length} · ${formatRupeesCompact(sum(soon))}',
              color: soon.isEmpty ? null : kUncategorizedInkColor,
            ),
            cell('Every month', formatRupeesCompact(monthly)),
          ],
        ),
      ),
    );
  }
}

class _BillRow extends ConsumerWidget {
  const _BillRow({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final account = accounts.where((a) => a.id == bill.accountId).firstOrNull;
    final category = categories.where((c) => c.id == bill.categoryId).firstOrNull;
    return InkWell(
      key: Key('bill-${bill.id}'),
      onTap: () => showBillActions(context, ref, bill),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            BillAvatar(bill: bill, category: category),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bill.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        formatRupeesCompact(bill.amountPaise),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Status first; the details wrap below it on a narrow screen.
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      BillStatusChip(bill: bill),
                      Text(
                        '${bill.kind == BillKind.emi ? 'EMI' : 'Bill'} · ${dueDayLabel(bill.dueDay)}'
                        '${account == null ? '' : ' · ${account.name}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('bill-reminder-${bill.id}'),
              tooltip: bill.reminderEnabled ? 'Reminder on (tap to turn off)' : 'Reminder off (tap to turn on)',
              icon: Icon(
                bill.reminderEnabled ? Icons.notifications_active : Icons.notifications_off_outlined,
                color: bill.reminderEnabled ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
              onPressed: () => _toggleReminder(context, ref, bill),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _toggleReminder(BuildContext context, WidgetRef ref, Bill bill) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(repositoryProvider).setBillReminder(bill.id, !bill.reminderEnabled);
    ref.read(revisionsProvider.notifier).bump(['recurring_bills']);
    messenger.showSnackBar(
      SnackBar(content: Text(bill.reminderEnabled ? 'No reminders for ${bill.name}' : 'Reminders on for ${bill.name}')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
  }
}

/// Mark paid / Edit / Delete for one bill.
Future<void> showBillActions(BuildContext context, WidgetRef ref, Bill bill) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(bill.name, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text('${formatRupees(bill.amountPaise)} · next due ${friendlyDate(bill.nextDueDate)}'),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('bill-action-paid'),
            leading: const Icon(Icons.task_alt),
            title: Text('Mark ${bill.nextDueMonth.label} paid'),
            subtitle: const Text('Optionally add the payment to Transactions'),
            onTap: () => Navigator.pop(context, 'paid'),
          ),
          ListTile(
            key: const Key('bill-action-edit'),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit bill'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            key: const Key('bill-action-delete'),
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: const Text('Delete bill'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'paid':
      await showMarkPaidSheet(context, ref, bill);
    case 'edit':
      await context.push('/bills/${bill.id}');
    case 'delete':
      await confirmDeleteBill(context, ref, bill);
  }
}

Future<bool> confirmDeleteBill(BuildContext context, WidgetRef ref, Bill bill) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${bill.name}?'),
      content: const Text('Its reminders stop. Payments already added to Transactions stay there.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(repositoryProvider).deleteBill(bill.id);
    ref.read(revisionsProvider.notifier).bump(['recurring_bills']);
    messenger.showSnackBar(SnackBar(content: Text('Deleted ${bill.name}')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Not deleted. ${describeError(e)}')));
    return false;
  }
}

/// "Mark October paid", with the option (on by default) to add the payment
/// to Transactions in the same step. The database does both at once and
/// never twice (mark_bill_paid), so a retry or the same tap on the web can't
/// double-count.
Future<void> showMarkPaidSheet(BuildContext context, WidgetRef ref, Bill bill) async {
  final result = await showModalBottomSheet<_PaidChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _MarkPaidSheet(bill: bill),
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!ref.read(isOnlineProvider)) {
    messenger.showSnackBar(const SnackBar(content: Text("There's no internet connection. Nothing was changed.")));
    return;
  }
  final repo = ref.read(repositoryProvider);
  final revisions = ref.read(revisionsProvider.notifier);
  final month = bill.nextDueMonth;
  final txnId = result.log ? const Uuid().v4() : null;
  try {
    final done = await repo.markBillPaid(
      billId: bill.id,
      month: month,
      txnId: txnId,
      amountPaise: result.amountPaise,
      paidOn: indiaToday(ref.read(clockProvider)),
      paymentMethod: result.method,
    );
    revisions.bump(['recurring_bills', 'transactions']);
    final logged = done.transactionId != null && !done.alreadyPaid;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          done.alreadyPaid
              ? '${bill.name} was already marked paid for ${month.label}.'
              : '${bill.name} marked paid for ${month.label}${logged ? ' and added to Transactions' : ''}.',
        ),
        action: done.alreadyPaid
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  try {
                    await repo.setBillPaidThrough(bill.id, bill.paidThroughMonth);
                    if (logged) await repo.deleteTransaction(done.transactionId!);
                    revisions.bump(['recurring_bills', 'transactions']);
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text("Couldn't undo. ${describeError(e)}")));
                  }
                },
              ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Not marked paid. ${describeError(e)}')));
  }
}

@immutable
class _PaidChoice {
  const _PaidChoice({required this.log, required this.amountPaise, required this.method});

  final bool log;
  final int amountPaise;
  final PaymentMethod method;
}

class _MarkPaidSheet extends ConsumerStatefulWidget {
  const _MarkPaidSheet({required this.bill});

  final Bill bill;

  @override
  ConsumerState<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends ConsumerState<_MarkPaidSheet> {
  bool _log = true;
  late final _amount = TextEditingController(text: AmountInput.fromPaise(widget.bill.amountPaise).text);
  PaymentMethod? _method;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bill = widget.bill;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final account = accounts.where((a) => a.id == bill.accountId).firstOrNull;
    final method = _method ?? defaultMethodFor(account?.type);
    final paise = parseRupeesToPaise(_amount.text);
    final amountOk = paise != null && paise > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mark ${bill.name} paid for ${bill.nextDueMonth.label}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('Due ${DateFormat('EEE, d MMM').format(bill.nextDueDate)}', style: theme.textTheme.bodySmall),
          SwitchListTile(
            key: const Key('paid-log-switch'),
            contentPadding: EdgeInsets.zero,
            value: _log,
            onChanged: (v) => setState(() => _log = v),
            title: const Text('Also add it to Transactions'),
            subtitle: Text('As an expense today${account == null ? '' : ', from ${account.name}'}'),
          ),
          if (_log) ...[
            TextField(
              key: const Key('paid-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount paid',
                prefixText: '₹ ',
                errorText: amountOk ? null : 'Enter an amount above zero',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: m == method,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('paid-confirm'),
            onPressed: !_log || amountOk
                ? () => Navigator.pop(
                    context,
                    _PaidChoice(log: _log, amountPaise: paise ?? bill.amountPaise, method: method),
                  )
                : null,
            icon: const Icon(Icons.task_alt),
            label: const Text('Mark paid'),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          if (onTap != null) Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_note, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text(
            'No bills yet.\nAdd electricity, water, gas, phone and internet bills and loan EMIs '
            'to be reminded at $kBillReminderTime before they are due.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
