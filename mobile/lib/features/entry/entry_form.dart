import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/offline_banner.dart';
import '../../core/theme.dart';
import '../../core/unsaved_changes.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'amount_keypad.dart';
import 'category_picker.dart';

/// Something saved during this Add session, shown in the "Just saved" panel.
class SavedEntry {
  const SavedEntry(this.txn);
  final Txn txn;
}

/// The transaction form, used by both Add (batch entry) and Edit.
///
/// Add mode is built for end-of-day batch logging: amount first on the
/// on-screen keypad, then description, and "Save & add another" keeps the
/// date, type, account and payment method for the next entry.
class EntryForm extends ConsumerStatefulWidget {
  const EntryForm({super.key, this.initial, this.onSavedAndClose});

  /// Null for a new transaction; the existing row when editing.
  final Txn? initial;

  /// Called after "Save" (add mode: save & leave; edit mode: save).
  final ValueChanged<Txn>? onSavedAndClose;

  bool get isEdit => initial != null;

  @override
  ConsumerState<EntryForm> createState() => EntryFormState();
}

class EntryFormState extends ConsumerState<EntryForm> {
  static const _uuid = Uuid();

  late TxnType _type;
  late AmountInput _amount;
  late DateTime _date;
  final _description = TextEditingController();
  final _descriptionFocus = FocusNode();
  final _scroll = ScrollController();
  String? _accountId;
  String? _toAccountId;
  PaymentMethod? _method;

  /// Null = let the database auto-categorize.
  String? _categoryId;

  /// Add mode only: client-generated id for the next insert, so retrying a
  /// save after an unclear failure can't create a duplicate. Renewed after
  /// each success. (Edit mode updates the row by its own id.)
  String? _insertId;

  bool _keypadVisible = true;
  bool _saving = false;
  bool _submitted = false;
  final List<SavedEntry> _saved = [];

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    final prefs = ref.read(entryPrefsProvider);
    if (t != null) {
      _type = t.type;
      _amount = AmountInput.fromPaise(t.amountPaise);
      _date = t.date;
      _description.text = t.description;
      _accountId = t.accountId;
      _toAccountId = t.toAccountId;
      _method = t.paymentMethod;
      _categoryId = t.categoryId;
      _keypadVisible = false;
      // Editing: typing in the description can make the form dirty.
      _description.addListener(() => setState(() {}));
    } else {
      _type = TxnType.expense;
      _amount = const AmountInput();
      _date = indiaToday(ref.read(clockProvider));
      _accountId = prefs.lastAccountId;
      _method = prefs.lastPaymentMethod;
      _insertId = _uuid.v4();
    }
    _descriptionFocus.addListener(() {
      if (_descriptionFocus.hasFocus && _keypadVisible) setState(() => _keypadVisible = false);
    });
    // Keep the selected account valid once accounts load (or change live).
    _reconcileAccounts(ref.read(accountsProvider).value ?? const <Account>[]);
    ref.listenManual(accountsProvider, (_, next) {
      final accounts = next.value;
      if (accounts != null) setState(() => _reconcileAccounts(accounts));
    });
  }

  @override
  void dispose() {
    _description.dispose();
    _scroll.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

  /// What the account pickers offer: active accounts, plus (when editing)
  /// the row's own accounts even if archived since.
  List<Account> _pickable(List<Account> accounts) =>
      pickableAccounts(accounts, keepIds: [widget.initial?.accountId, widget.initial?.toAccountId]);

  /// Keeps the selected accounts pickable. A remembered last account that
  /// has been archived falls back to the Cash account, else the first one.
  void _reconcileAccounts(List<Account> all) {
    final accounts = _pickable(all);
    if (accounts.isEmpty) return;
    final ids = accounts.map((a) => a.id).toSet();
    if (_accountId == null || !ids.contains(_accountId)) {
      final active = accounts.where((a) => !a.archived);
      final fallback = active.where((a) => a.type == AccountType.cash).firstOrNull ?? active.firstOrNull;
      _accountId = (fallback ?? accounts.first).id;
    }
    if (_toAccountId != null && !ids.contains(_toAccountId)) _toAccountId = null;
  }

  /// Edit mode: something differs from the row as it was loaded.
  bool get _dirty {
    final t = widget.initial;
    if (t == null) return false;
    return _type != t.type ||
        _amount.paise != t.amountPaise ||
        _date != t.date ||
        _description.text.trim() != t.description.trim() ||
        _accountId != t.accountId ||
        (_type == TxnType.transfer && _toAccountId != t.toAccountId) ||
        _method != t.paymentMethod ||
        (_type != TxnType.transfer && _categoryId != t.categoryId);
  }

  String? get _amountError => _submitted && _amount.paise <= 0 ? 'Enter an amount' : null;

  String? get _methodError =>
      _submitted && _type == TxnType.expense && _method == null ? 'Choose how you paid' : null;

  String? get _toAccountError {
    if (!_submitted || _type != TxnType.transfer) return null;
    if (_toAccountId == null) return 'Choose the account the money went to';
    if (_toAccountId == _accountId) return 'Must be different from the "From" account';
    return null;
  }

  bool get _valid {
    if (_amount.paise <= 0 || _accountId == null) return false;
    if (_type == TxnType.expense && _method == null) return false;
    if (_type == TxnType.transfer && (_toAccountId == null || _toAccountId == _accountId)) return false;
    return true;
  }

  TxnDraft _draft() => TxnDraft(
        date: _date,
        amountPaise: _amount.paise,
        description: _description.text,
        type: _type,
        accountId: _accountId!,
        toAccountId: _type == TxnType.transfer ? _toAccountId : null,
        categoryId: _type == TxnType.transfer ? null : _categoryId,
        paymentMethod: _method,
      );

  // ---------------------------------------------------------------- actions

  Future<void> _save({required bool addAnother}) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);
    if (!_valid) {
      // Errors are shown inline next to each field. (No SnackBar: it would
      // cover the keypad and swallow taps.)
      _scrollToTop();
      return;
    }
    if (!ref.read(isOnlineProvider)) {
      await _showSaveFailed("There's no internet connection.");
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final draft = _draft();
    final Txn saved;
    try {
      saved = widget.isEdit
          ? await repo.updateTransaction(widget.initial!.id, draft)
          : await repo.insertTransaction(_insertId!, draft);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _showSaveFailed(describeError(e));
      return;
    }
    if (!mounted) return;

    // Remembered for the next entry (device preference, not data).
    await ref.read(entryPrefsProvider).remember(accountId: saved.accountId, method: saved.paymentMethod);

    // Show the category the database picked, even if it just auto-created it.
    final known = ref.read(categoriesProvider).value ?? const <Category>[];
    if (saved.categoryId != null && !known.any((c) => c.id == saved.categoryId)) {
      ref.invalidate(categoriesProvider);
    }
    ref.read(revisionsProvider.notifier).bump(['transactions']);

    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.isEdit || !addAnother) {
      _snack('Saved ${formatRupees(saved.amountPaise)}${_descSuffix(saved)}');
      widget.onSavedAndClose?.call(saved);
      return;
    }

    setState(() {
      _saved.insert(0, SavedEntry(saved));
      _amount = const AmountInput();
      _description.clear();
      _categoryId = null;
      _submitted = false;
      _insertId = _uuid.v4();
      _keypadVisible = true;
    });
    // Confirmation is the 'Just saved' panel at the top. A SnackBar here
    // would sit on top of the keypad and swallow the next amount's taps.
    _scrollToTop();
  }

  String _descSuffix(Txn t) => t.description.isEmpty ? '' : ' · ${t.description}';

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _snack(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 3),
      ));
  }

  Future<void> _showSaveFailed(String reason) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.error_outline),
          title: const Text('Not saved'),
          content: Text('$reason\n\nYour entry is still on the screen. Nothing was lost; try saving again.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );

  Future<void> _pickDate() async {
    final today = indiaToday(ref.read(clockProvider));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: DateTime(today.year + 1, 12, 31),
      helpText: 'Transaction date',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _onKey(String key) => setState(() {
        _amount = key == 'clear' ? const AmountInput() : _amount.press(key);
      });

  void _keypadDone() {
    setState(() => _keypadVisible = false);
    _descriptionFocus.requestFocus();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final accounts = accountsAsync.value ?? const <Account>[];

    if (accountsAsync.hasError && accounts.isEmpty) {
      return LoadError(
        message: "Couldn't load your accounts. ${describeError(accountsAsync.error!)}",
        onRetry: () => ref.invalidate(accountsProvider),
      );
    }

    final theme = Theme.of(context);
    final form = Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            children: [
              if (_saved.isNotEmpty) _JustSaved(entries: _saved, categories: categories, accounts: accounts),
              _typeSelector(),
              const SizedBox(height: 10),
              _amountField(theme),
              const SizedBox(height: 10),
              TextField(
                key: const Key('entry-description'),
                controller: _description,
                focusNode: _descriptionFocus,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onTap: () => setState(() => _keypadVisible = false),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. Swiggy dinner, DMart, Electricity bill',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              _accountRow(_pickable(accounts)),
              const SizedBox(height: 8),
              _methodRow(theme),
              const SizedBox(height: 8),
              _dateRow(theme),
              if (_type != TxnType.transfer) ...[
                const SizedBox(height: 10),
                _categoryField(categories),
              ],
              const SizedBox(height: 14),
              _buttons(),
            ],
          ),
        ),
        if (_keypadVisible)
          AmountKeypad(onKey: _onKey, onDone: _keypadDone, doneLabel: 'Next'),
      ],
    );
    // Editing: leaving with unsaved changes asks first. (Add keeps its
    // entry when switching tabs, so there is nothing to lose there.)
    return widget.isEdit ? UnsavedChangesScope(dirty: _dirty, child: form) : form;
  }

  Widget _typeSelector() => SegmentedButton<TxnType>(
        key: const Key('entry-type'),
        showSelectedIcon: false,
        segments: [
          for (final t in TxnType.values) ButtonSegment(value: t, icon: Icon(t.icon, size: 18), label: Text(t.label)),
        ],
        selected: {_type},
        onSelectionChanged: (s) => setState(() {
          final next = s.first;
          // A category of the wrong kind can't stay selected.
          if (next != _type) _categoryId = null;
          _type = next;
        }),
      );

  Widget _amountField(ThemeData theme) {
    final color = switch (_type) {
      TxnType.expense => kExpenseColor,
      TxnType.income => kIncomeColor,
      TxnType.transfer => kTransferColor,
    };
    return InkWell(
      key: const Key('entry-amount'),
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() => _keypadVisible = true);
      },
      child: InputDecorator(
        isFocused: _keypadVisible,
        decoration: InputDecoration(labelText: 'Amount', errorText: _amountError),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('₹ ', style: theme.textTheme.headlineSmall?.copyWith(color: color)),
            Expanded(
              child: Text(
                _amount.display,
                key: const Key('entry-amount-text'),
                style: theme.textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountRow(List<Account> accounts) {
    DropdownMenuItem<String> item(Account a) => DropdownMenuItem(
          value: a.id,
          child: Row(children: [
            Icon(a.type.icon, size: 18, color: a.type.color),
            const SizedBox(width: 8),
            Flexible(child: Text(accountPickerLabel(a), overflow: TextOverflow.ellipsis)),
          ]),
        );
    // Keyed on the value: the field only reads initialValue once, and the
    // account can be filled in after it first shows (accounts still loading).
    final from = KeyedSubtree(
      key: ValueKey('entry-account-$_accountId'),
      child: DropdownButtonFormField<String>(
        key: const Key('entry-account'),
        initialValue: _accountId,
        isExpanded: true,
        decoration: InputDecoration(labelText: _type == TxnType.transfer ? 'From account' : 'Account'),
        items: [for (final a in accounts) item(a)],
        onChanged: (v) => setState(() => _accountId = v),
      ),
    );
    if (_type != TxnType.transfer) return from;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: from),
        const Padding(padding: EdgeInsets.only(top: 12, left: 4, right: 4), child: Icon(Icons.arrow_forward, size: 18)),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('entry-to-account-$_toAccountId'),
            child: DropdownButtonFormField<String>(
              key: const Key('entry-to-account'),
              initialValue: _toAccountId,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'To account', errorText: _toAccountError),
              items: [for (final a in accounts) item(a)],
              onChanged: (v) => setState(() => _toAccountId = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _methodRow(ThemeData theme) {
    final required = _type == TxnType.expense;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: required ? 'Paid by' : 'Paid by (optional)',
        errorText: _methodError,
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final m in PaymentMethod.values)
            ChoiceChip(
              key: Key('method-${m.db}'),
              avatar: Icon(m.icon, size: 16),
              label: Text(m.label),
              selected: _method == m,
              visualDensity: VisualDensity.compact,
              onSelected: (sel) => setState(() => _method = sel ? m : (required ? _method : null)),
            ),
        ],
      ),
    );
  }

  Widget _dateRow(ThemeData theme) {
    final clock = ref.read(clockProvider);
    final today = indiaToday(clock);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final dateText = friendlyDate(_date, clock: clock);
    final field = InkWell(
      key: const Key('entry-date'),
      onTap: _pickDate,
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
        child: Text(dateText, key: const Key('entry-date-text')),
      ),
    );
    // Shortcuts; the filled chip is enough to show which (no checkmark,
    // so they stay narrow).
    final chips = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ChoiceChip(
          key: const Key('entry-date-today'),
          label: const Text('Today'),
          showCheckmark: false,
          selected: _date == today,
          onSelected: (_) => setState(() => _date = today),
        ),
        ChoiceChip(
          key: const Key('entry-date-yesterday'),
          label: const Text('Yesterday'),
          showCheckmark: false,
          selected: _date == yesterday,
          onSelected: (_) => setState(() => _date = yesterday),
        ),
      ],
    );
    // Chips beside the date when the date still fits on one line next to
    // them; below it on a narrow phone or with a large system font.
    return LayoutBuilder(builder: (context, constraints) {
      final chipsWidth = _labelWidth(context, 'Today') + _labelWidth(context, 'Yesterday') + _kDateChipsChrome;
      final dateWidth = _textWidth(context, dateText, theme.textTheme.bodyLarge) + _kDateFieldChrome;
      if (chipsWidth + 6 + dateWidth <= constraints.maxWidth) {
        return Row(children: [Expanded(child: field), const SizedBox(width: 6), chips]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [field, const SizedBox(height: 4), chips],
      );
    });
  }

  Widget _categoryField(List<Category> categories) {
    final selected = categories.where((c) => c.id == _categoryId).firstOrNull;
    final theme = Theme.of(context);
    return InkWell(
      key: const Key('entry-category'),
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        FocusScope.of(context).unfocus();
        final choice = await showCategoryPicker(
          context,
          categories: categories,
          kind: _type,
          selectedId: _categoryId,
          editing: widget.isEdit,
        );
        if (choice != null && mounted) setState(() => _categoryId = choice.id);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Category (optional)',
          helperText: widget.isEdit
              ? 'Changing the category teaches Ventrafin for next time.'
              : 'Leave on Auto and Ventrafin picks one from the description.',
          suffixIcon: const Icon(Icons.arrow_drop_down),
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
        ),
        // No category: "Auto" for a new entry (the database picks one), but
        // "Uncategorized" when editing, as the list calls it.
        child: Row(children: [
          if (selected != null)
            CategoryAvatar(category: selected, size: 24)
          else if (widget.isEdit)
            const UncategorizedAvatar(size: 24)
          else
            const AutoCategoryAvatar(size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              selected != null
                  ? '${selected.name}${selected.archived ? ' (archived)' : ''}'
                  : widget.isEdit
                  ? 'Uncategorized'
                  : 'Auto',
              key: const Key('entry-category-text'),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buttons() {
    final spinner = const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
    if (widget.isEdit) {
      return FilledButton.icon(
        key: const Key('entry-save'),
        onPressed: _saving ? null : () => _save(addAnother: false),
        icon: _saving ? spinner : const Icon(Icons.check),
        label: const Text('Save changes'),
      );
    }
    const closeLabel = 'Save & close';
    const anotherLabel = 'Save & add another';
    final close = OutlinedButton(
      key: const Key('entry-save-close'),
      onPressed: _saving ? null : () => _save(addAnother: false),
      child: const FittedBox(fit: BoxFit.scaleDown, child: Text(closeLabel, maxLines: 1, softWrap: false)),
    );
    final another = FilledButton.icon(
      key: const Key('entry-save-another'),
      onPressed: _saving ? null : () => _save(addAnother: true),
      icon: _saving ? spinner : const Icon(Icons.playlist_add),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text(anotherLabel, maxLines: 1, softWrap: false)),
    );
    // Side by side when both labels fit on one line; on a narrow phone or
    // with a large system font, stacked full width instead of wrapping.
    // (Labels only shrink as a last resort, at extreme font sizes.)
    return LayoutBuilder(builder: (context, constraints) {
      final needed = _labelWidth(context, closeLabel) + _labelWidth(context, anotherLabel) + _kSaveButtonsChrome;
      if (needed <= constraints.maxWidth) {
        return Row(children: [close, const SizedBox(width: 8), Expanded(child: another)]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [another, const SizedBox(height: 6), close],
      );
    });
  }

  /// Horizontal space the two save buttons need besides their label text:
  /// Material 3 padding (outlined 24+24, filled-with-icon 16+24), the 18 dp
  /// icon and its 8 dp gap, and the 8 dp between the buttons.
  static const double _kSaveButtonsChrome = 48 + 40 + 18 + 8 + 8;

  /// Besides their labels: two chips' padding and borders (about 35 dp
  /// each, rounded up) and the 4 dp between them.
  static const double _kDateChipsChrome = 2 * 38 + 4;

  /// Besides the date text: the field's padding and the calendar icon.
  static const double _kDateFieldChrome = 24 + 48;

  double _labelWidth(BuildContext context, String text) =>
      _textWidth(context, text, Theme.of(context).textTheme.labelLarge);

  double _textWidth(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// "Just saved" panel: what was stored (as the database returned it,
/// including the category it auto-assigned), newest first.
class _JustSaved extends StatelessWidget {
  const _JustSaved({required this.entries, required this.categories, required this.accounts});

  final List<SavedEntry> entries;
  final List<Category> categories;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entries.where((e) => e.txn.type == TxnType.expense).fold<int>(0, (s, e) => s + e.txn.amountPaise);
    return Card(
      key: const Key('just-saved'),
      color: Colors.green.shade50,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${entries.length} saved this session'
                  '${total > 0 ? ' · ${formatRupees(total)} spent' : ''}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            for (final e in entries.take(3)) _line(context, e.txn),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, Txn t) {
    final category = categories.where((c) => c.id == t.categoryId).firstOrNull;
    final account = accounts.where((a) => a.id == t.accountId).firstOrNull;
    final categoryText = switch (t) {
      Txn(type: TxnType.transfer) => 'Transfer',
      Txn(categoryId: null) => 'Uncategorized',
      _ => '${category?.name ?? 'New category'}${t.autoCategorized ? ' (auto)' : ''}',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TxnAvatar(txn: t, category: category, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${formatRupees(t.amountPaise)} · ${t.description.isEmpty ? '(no description)' : t.description}'
              ' · $categoryText · ${account?.name ?? ''}${t.paymentMethod != null ? '/${t.paymentMethod!.label}' : ''}'
              ' · ${DateFormat('d MMM').format(t.date)}',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
