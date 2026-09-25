import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/offline_banner.dart';
import '../../core/unsaved_changes.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Accounts (PRD § 4.1): the active ones, then the archived ones with
/// Restore. Tap an account to rename it, change its type or archive it.
/// Accounts are archived, never deleted: their transactions and bills keep
/// them.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accountsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-account'),
        onPressed: () => showAccountEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
      ),
      body: switch (async) {
        AsyncValue(:final value?) => ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final a in value.where((a) => !a.archived))
                ListTile(
                  key: Key('account-${a.id}'),
                  leading: AccountAvatar(type: a.type, size: 34),
                  title: Text(a.name),
                  subtitle: Text(a.type.label),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => showAccountEditor(context, account: a),
                ),
              if (value.any((a) => a.archived)) ...[
                _SectionHeader(text: 'Archived'),
                for (final a in value.where((a) => a.archived))
                  ListTile(
                    key: Key('account-${a.id}'),
                    leading: Opacity(opacity: 0.6, child: AccountAvatar(type: a.type, size: 34)),
                    title: Text(a.name),
                    subtitle: Text('${a.type.label} · archived'),
                    trailing: TextButton(
                      key: Key('restore-account-${a.id}'),
                      onPressed: () => _restore(context, ref, a),
                      child: const Text('Restore'),
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Tap an account to rename it, change its type or archive it. '
                  'An archived account disappears from the account pickers; '
                  'its transactions and bills keep it.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        AsyncValue(:final error?) => LoadError(
            message: describeError(error),
            onRetry: () => ref.invalidate(accountsProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, Account a) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!ref.read(isOnlineProvider)) {
      messenger.showSnackBar(const SnackBar(content: Text("There's no internet connection. Nothing was changed.")));
      return;
    }
    try {
      await ref.read(repositoryProvider).setAccountArchived(a.id, false);
      ref.read(revisionsProvider.notifier).bump(['accounts']);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Restored ${a.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Not restored. ${describeError(e)}')));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, style: theme.textTheme.labelLarge),
    );
  }
}

/// "Add account" ([account] null) or "Edit account".
Future<void> showAccountEditor(BuildContext context, {Account? account}) {
  return showGuardedSheet<void>(
    context: context,
    builder: (context) => AccountEditSheet(account: account),
  );
}

/// Name and type of an account; editing an active one also offers Archive.
class AccountEditSheet extends ConsumerStatefulWidget {
  const AccountEditSheet({super.key, this.account});

  /// Null to add a new account.
  final Account? account;

  @override
  ConsumerState<AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends ConsumerState<AccountEditSheet> {
  static const _newType = AccountType.bank;

  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late AccountType _type = widget.account?.type ?? _newType;

  /// Generated once, so retrying a failed save can't add the account twice.
  final _newId = const Uuid().v4();

  bool _tried = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _changed {
    final a = widget.account;
    if (a == null) return _name.text.trim().isNotEmpty || _type != _newType;
    return _name.text.trim() != a.name || _type != a.type;
  }

  String? _nameError(List<Account> accounts) =>
      accountNameError(_name.text, existing: accounts, exceptId: widget.account?.id);

  Future<void> _save(List<Account> accounts) async {
    setState(() => _tried = true);
    if (_nameError(accounts) != null) return;
    if (!ref.read(isOnlineProvider)) {
      setState(() => _error = "There's no internet connection. Nothing was saved.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.text.trim();
    try {
      final repo = ref.read(repositoryProvider);
      if (_isEdit) {
        await repo.updateAccount(widget.account!.id, name: name, type: _type);
      } else {
        await repo.insertAccount(_newId, name: name, type: _type);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Not saved. ${describeError(e)}';
      });
      return;
    }
    ref.read(revisionsProvider.notifier).bump(['accounts']);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    messenger?.showSnackBar(SnackBar(content: Text(_isEdit ? 'Saved $name' : 'Added $name')));
  }

  Future<void> _archive() async {
    final account = widget.account!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${account.name}?'),
        content: const Text(
          'It disappears from the account pickers. Its transactions and bills keep it, '
          'and you can restore it any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm-archive'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!ref.read(isOnlineProvider)) {
      setState(() => _error = "There's no internet connection. Nothing was changed.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).setAccountArchived(account.id, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Not archived. ${describeError(e)}';
      });
      return;
    }
    ref.read(revisionsProvider.notifier).bump(['accounts']);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    messenger?.showSnackBar(SnackBar(content: Text('Archived ${account.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final account = widget.account;
    final nameError = _nameError(accounts);
    // An empty name only complains once something was typed or Save tapped.
    final showNameError = _tried || _name.text.isNotEmpty || _isEdit;
    final lastActive = account != null && !account.archived && accounts.where((a) => !a.archived).length <= 1;

    return UnsavedChangesScope(
      dirty: _changed,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit account' : 'Add account', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                key: const Key('account-name'),
                controller: _name,
                autofocus: !_isEdit,
                maxLength: kAccountNameMaxLength,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. HDFC savings, SBI credit card',
                  errorText: showNameError ? nameError : null,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AccountType>(
                key: const Key('account-type'),
                showSelectedIcon: false,
                segments: [
                  for (final t in AccountType.values)
                    ButtonSegment(value: t, icon: Icon(t.icon, size: 18), label: Text(t.label)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.maybePop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: const Key('account-save'),
                    onPressed: _saving || (_isEdit && !_changed) ? null : () => _save(accounts),
                    icon: _saving
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(_isEdit ? 'Save' : 'Add account'),
                  ),
                ),
              ]),
              if (account != null && !account.archived) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton.icon(
                    key: const Key('account-archive'),
                    onPressed: _saving || lastActive ? null : _archive,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lastActive ? kKeepOneActiveAccount : 'Hides it from the pickers; its entries stay.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
