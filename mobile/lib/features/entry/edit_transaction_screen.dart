import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/money.dart';
import '../../core/offline_banner.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'entry_form.dart';

/// Edit (and delete) one transaction. Changing its category here feeds the
/// database's learning trigger.
///
/// Watches the row live: if it's changed or deleted on another device while
/// open, a banner says so instead of silently overwriting.
class EditTransactionScreen extends ConsumerStatefulWidget {
  const EditTransactionScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends ConsumerState<EditTransactionScreen> {
  /// The version the form was filled from.
  Txn? _base;
  int _formGeneration = 0;
  bool _deleting = false;

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/transactions');
    }
  }

  Future<void> _delete(Txn t) async {
    final ok = await confirmDelete(context, t);
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(repositoryProvider).deleteTransaction(t.id);
      ref.read(hiddenTxnIdsProvider.notifier).hide(t.id);
      ref.read(revisionsProvider.notifier).bump(['transactions']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${formatRupees(t.amountPaise)}')));
      _close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not deleted'),
          content: Text(describeError(e)),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(transactionProvider(widget.id));
    final latest = async.value;
    _base ??= latest;

    final changedRemotely = _base != null && latest != null && latest.updatedAt != _base!.updatedAt;
    final deletedRemotely = _base != null && async.hasValue && latest == null && !_deleting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit transaction'),
        actions: [
          if (_base != null && !deletedRemotely)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleting ? null : () => _delete(_base!),
            ),
        ],
      ),
      body: switch (_base) {
        null when async.hasError => LoadError(
            message: describeError(async.error!),
            onRetry: () => ref.invalidate(transactionProvider(widget.id)),
          ),
        null when async.hasValue => const Center(child: Text('This transaction no longer exists.')),
        null => const Center(child: CircularProgressIndicator()),
        final base => Column(
            children: [
              if (deletedRemotely)
                const _Banner(
                  icon: Icons.delete_forever,
                  text: 'This transaction was deleted on another device.',
                ),
              if (changedRemotely && !deletedRemotely)
                _Banner(
                  icon: Icons.sync_problem,
                  text: 'This transaction was changed on another device.',
                  action: TextButton(
                    onPressed: () => setState(() {
                      _base = latest;
                      _formGeneration++;
                    }),
                    child: const Text('Load latest'),
                  ),
                ),
              Expanded(
                child: IgnorePointer(
                  ignoring: deletedRemotely,
                  child: EntryForm(
                    key: ValueKey('${base.id}-$_formGeneration'),
                    initial: base,
                    // Our own save changes updated_at; record it so it isn't
                    // mistaken for a change from another device.
                    onSavedAndClose: (saved) {
                      _base = saved;
                      _close();
                    },
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: Icon(icon),
      content: Text(text),
      actions: [action ?? const SizedBox.shrink()],
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
    );
  }
}

/// Shared delete confirmation (edit screen and swipe-to-delete).
Future<bool> confirmDelete(BuildContext context, Txn t) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this transaction?'),
      content: Text(
        '${formatRupees(t.amountPaise)}'
        '${t.description.isEmpty ? '' : ' · ${t.description}'}\n\n'
        'This removes it from both the phone and the web app. It cannot be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
