import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/money.dart';
import '../../core/unsaved_changes.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../entry/category_picker.dart';
import '../reminders/reminder_plan.dart';
import 'bill_visuals.dart';
import 'bills_screen.dart';

/// Add a bill ([billId] null) or edit one.
class BillFormScreen extends ConsumerStatefulWidget {
  const BillFormScreen({super.key, this.billId});

  final String? billId;

  @override
  ConsumerState<BillFormScreen> createState() => _BillFormScreenState();
}

class _BillFormScreenState extends ConsumerState<BillFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  BillKind _kind = BillKind.utility;
  int _dueDay = 10;
  String? _accountId;
  String? _categoryId;
  bool _reminder = true;
  bool _filled = false;
  bool _saving = false;
  bool _tried = false;
  String? _error;

  /// Generated once, so retrying a failed save can't add the bill twice.
  final _newId = const Uuid().v4();

  /// The form's values when it was filled in, to tell whether anything
  /// changed since (null until then).
  _BillValues? _filledWith;

  _BillValues get _values => (
    name: _name.text.trim(),
    paise: parseRupeesToPaise(_amount.text),
    kind: _kind,
    dueDay: _dueDay,
    accountId: _accountId,
    categoryId: _categoryId,
    reminder: _reminder,
  );

  /// Something was changed and not saved yet.
  bool get _dirty {
    final filled = _filledWith;
    if (filled == null) return _name.text.trim().isNotEmpty || _amount.text.trim().isNotEmpty;
    return _values != filled;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _fill(Bill? bill, List<Account> accounts) {
    if (_filled) return;
    if (bill != null) {
      _name.text = bill.name;
      _amount.text = AmountInput.fromPaise(bill.amountPaise).text;
      _kind = bill.kind;
      _dueDay = bill.dueDay;
      _accountId = bill.accountId;
      _categoryId = bill.categoryId;
      _reminder = bill.reminderEnabled;
      _filled = true;
      _filledWith = _values;
    } else if (widget.billId == null && accounts.isNotEmpty) {
      final active = accounts.where((a) => !a.archived);
      _accountId =
          (active.where((a) => a.type == AccountType.bank).firstOrNull ?? active.firstOrNull ?? accounts.first).id;
      _filled = true;
      // What was typed before the accounts arrived still counts as a change.
      _filledWith = (
        name: '',
        paise: null,
        kind: BillKind.utility,
        dueDay: 10,
        accountId: _accountId,
        categoryId: null,
        reminder: true,
      );
    }
  }

  String? get _nameError {
    final n = _name.text.trim();
    if (n.isEmpty) return 'Enter a name, like "BESCOM electricity" or "Home loan EMI"';
    if (n.runes.length > kBillNameMaxLength) return 'Keep it to $kBillNameMaxLength characters or fewer';
    return null;
  }

  int? get _paise {
    final p = parseRupeesToPaise(_amount.text);
    return p != null && p > 0 ? p : null;
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_nameError != null || _paise == null || _accountId == null) return;
    if (!ref.read(isOnlineProvider)) {
      setState(() => _error = "There's no internet connection. Nothing was saved.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = BillDraft(
      name: _name.text,
      kind: _kind,
      amountPaise: _paise!,
      dueDay: _dueDay,
      accountId: _accountId!,
      categoryId: _categoryId,
      reminderEnabled: _reminder,
    );
    try {
      final repo = ref.read(repositoryProvider);
      if (widget.billId == null) {
        await repo.insertBill(_newId, draft);
      } else {
        await repo.updateBill(widget.billId!, draft);
      }
      ref.read(revisionsProvider.notifier).bump(['recurring_bills']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.billId == null ? 'Added ${draft.name.trim()}' : 'Saved ${draft.name.trim()}')),
      );
      _close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeError(e);
        });
      }
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go('/bills');

  Future<void> _pickCategory(List<Category> categories) async {
    final choice = await showCategoryPicker(
      context,
      categories: categories,
      kind: TxnType.expense,
      selectedId: _categoryId,
    );
    if (choice != null) setState(() => _categoryId = choice.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final bills = ref.watch(billsProvider).value;
    final bill = widget.billId == null ? null : bills?.where((b) => b.id == widget.billId).firstOrNull;
    _fill(bill, accounts);
    final missing = widget.billId != null && bills != null && bill == null;
    final category = categories.where((c) => c.id == _categoryId).firstOrNull;
    final masterOff = ref.watch(effectiveProfileProvider)?.billRemindersEnabled == false;
    // Active accounts, plus the bill's own one if it has been archived since.
    final pickable = pickableAccounts(accounts, keepIds: [bill?.accountId]);

    return UnsavedChangesScope(
      dirty: _dirty && !missing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.billId == null ? 'Add bill' : 'Edit bill'),
          actions: [
            if (bill != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirmDeleteBill(context, ref, bill) && mounted) _close();
                },
              ),
          ],
        ),
        body: missing
            ? const Center(child: Text('This bill was deleted, perhaps on the web.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    key: const Key('bill-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: 'Name', errorText: _tried ? _nameError : null),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<BillKind>(
                    segments: const [
                      ButtonSegment(
                        value: BillKind.utility,
                        icon: Icon(Icons.receipt_long),
                        label: Text('Utility bill'),
                      ),
                      ButtonSegment(value: BillKind.emi, icon: Icon(Icons.event_repeat), label: Text('Loan EMI')),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('bill-amount'),
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Usual amount',
                            prefixText: '₹ ',
                            errorText: _tried && _paise == null ? 'Enter an amount above zero' : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 130,
                        child: DropdownButtonFormField<int>(
                          key: const Key('bill-due-day'),
                          initialValue: _dueDay,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Due day'),
                          menuMaxHeight: 360,
                          items: [
                            for (var d = 1; d <= 31; d++)
                              DropdownMenuItem(value: d, child: Text(d == 31 ? '31 (last)' : '$d')),
                          ],
                          onChanged: (d) => setState(() => _dueDay = d ?? _dueDay),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      'Due on the ${dueDayLabel(_dueDay)}. Shorter months use their last day.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('bill-account-$_accountId'),
                    initialValue: _accountId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Paid from'),
                    items: [
                      for (final a in pickable)
                        DropdownMenuItem(
                          value: a.id,
                          child: Row(
                            children: [
                              AccountAvatar(type: a.type, size: 22),
                              const SizedBox(width: 8),
                              Flexible(child: Text(accountPickerLabel(a), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _accountId = v),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Category'),
                    child: InkWell(
                      key: const Key('bill-category'),
                      onTap: () => _pickCategory(categories),
                      child: Row(
                        children: [
                          category == null
                              ? const AutoCategoryAvatar(size: 24)
                              : CategoryAvatar(category: category, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              category == null
                                  ? 'Auto (from the name)'
                                  : '${category.name}${category.archived ? ' (archived)' : ''}',
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    key: const Key('bill-reminder'),
                    contentPadding: EdgeInsets.zero,
                    value: _reminder,
                    onChanged: (v) => setState(() => _reminder = v),
                    title: const Text('Remind me'),
                    subtitle: Text(
                      masterOff
                          ? 'Bill reminders are switched off in Settings'
                          : 'Before the due date and on the day, at $kBillReminderTime',
                    ),
                  ),
                  if (bill != null) _PaidThrough(bill: bill),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('bill-save'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(widget.billId == null ? 'Add bill' : 'Save'),
                  ),
                ],
              ),
      ),
    );
  }
}

typedef _BillValues = ({
  String name,
  int? paise,
  BillKind kind,
  int dueDay,
  String? accountId,
  String? categoryId,
  bool reminder,
});

/// "Paid up to September 2026", with a way to take the last month back.
class _PaidThrough extends ConsumerWidget {
  const _PaidThrough({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.task_alt),
          title: Text('Paid up to ${bill.paidThroughMonth.label}'),
          subtitle: Text('Next: ${bill.nextDueMonth.label}, ${billStatusLabel(bill).toLowerCase()}'),
        ),
        TextButton.icon(
          icon: const Icon(Icons.undo),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await ref.read(repositoryProvider).setBillPaidThrough(bill.id, bill.paidThroughMonth.previous);
              ref.read(revisionsProvider.notifier).bump(['recurring_bills']);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    '${bill.paidThroughMonth.label} marked unpaid. '
                    'Any payment already added stays in Transactions.',
                  ),
                ),
              );
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
            }
          },
          label: Text('Mark ${bill.paidThroughMonth.label} unpaid'),
        ),
      ],
    );
  }
}
