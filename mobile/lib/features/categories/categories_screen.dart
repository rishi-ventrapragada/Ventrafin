import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_style.dart';
import '../../core/errors.dart';
import '../../core/offline_banner.dart';
import '../../core/unsaved_changes.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Categories with their icons and colours (PRD § 4.3). Tap one to rename
/// it, restyle it from the curated set or archive it; "Add" in a section
/// adds one of that kind. Archived categories are listed last, with
/// Restore. Updates live, e.g. when auto-categorization creates one.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final theme = Theme.of(context);
    Widget header(String text, {Widget? action}) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: EdgeInsets.fromLTRB(12, action == null ? 6 : 0, 4, action == null ? 6 : 0),
          child: Row(children: [
            Expanded(child: Text(text, style: theme.textTheme.labelLarge)),
            ?action,
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: switch (categories) {
        AsyncValue(:final value?) => ListView(children: [
            for (final kind in [TxnType.expense, TxnType.income]) ...[
              header(
                '${kind.label} categories',
                action: TextButton.icon(
                  key: Key('add-category-${kind.db}'),
                  onPressed: () => showCategoryAdder(context, kind: kind),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ),
              for (final c in _sorted(value.where((c) => c.kind == kind && !c.archived)))
                ListTile(
                  key: Key('category-${c.id}'),
                  leading: CategoryAvatar(category: c, size: 34),
                  title: Text(c.name),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => showCategoryEditor(context, c),
                ),
            ],
            if (value.any((c) => c.archived)) ...[
              header('Archived'),
              for (final c in _sorted(value.where((c) => c.archived)))
                ListTile(
                  key: Key('category-${c.id}'),
                  leading: Opacity(opacity: 0.6, child: CategoryAvatar(category: c, size: 34)),
                  title: Text(c.name),
                  subtitle: Text('${c.kind.label} · archived'),
                  trailing: TextButton(
                    key: Key('restore-category-${c.id}'),
                    onPressed: () => _restore(context, ref, c),
                    child: const Text('Restore'),
                  ),
                  onTap: () => showCategoryEditor(context, c),
                ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tap a category to rename it, change its icon and colour, or archive it. '
                'Renaming keeps its automatic matches: if Food becomes "Khana", Swiggy still goes there.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ]),
        AsyncValue(:final error?) => LoadError(
            message: describeError(error),
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  static List<Category> _sorted(Iterable<Category> cs) =>
      cs.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> _restore(BuildContext context, WidgetRef ref, Category c) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!ref.read(isOnlineProvider)) {
      messenger.showSnackBar(const SnackBar(content: Text("There's no internet connection. Nothing was changed.")));
      return;
    }
    try {
      await ref.read(repositoryProvider).setCategoryArchived(c.id, false);
      ref.read(revisionsProvider.notifier).bump(['categories']);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Restored ${c.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Not restored. ${describeError(e)}')));
    }
  }
}

Future<void> showCategoryEditor(BuildContext context, Category category) {
  return showGuardedSheet<void>(
    context: context,
    builder: (context) => CategoryEditSheet(category: category),
  );
}

/// "Add category": name and kind only; the database picks the icon and
/// colour (both can be changed afterwards).
Future<void> showCategoryAdder(BuildContext context, {required TxnType kind}) {
  return showGuardedSheet<void>(
    context: context,
    builder: (context) => CategoryAddSheet(kind: kind),
  );
}

class CategoryAddSheet extends ConsumerStatefulWidget {
  const CategoryAddSheet({super.key, required this.kind});

  /// Preselected: the section "Add" was tapped in.
  final TxnType kind;

  @override
  ConsumerState<CategoryAddSheet> createState() => _CategoryAddSheetState();
}

class _CategoryAddSheetState extends ConsumerState<CategoryAddSheet> {
  final _name = TextEditingController();
  late TxnType _kind = widget.kind;
  bool _tried = false;
  bool _saving = false;
  String? _error;

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

  String? _nameError(List<Category> existing) => categoryNameError(_name.text, kind: _kind, existing: existing);

  Future<void> _save(List<Category> existing) async {
    setState(() => _tried = true);
    if (_nameError(existing) != null) return;
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
      await ref.read(repositoryProvider).insertCategory(name: name, kind: _kind);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Not saved. ${describeError(e)}';
      });
      return;
    }
    ref.read(revisionsProvider.notifier).bump(['categories']);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    messenger?.showSnackBar(SnackBar(content: Text('Added $name')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = ref.watch(categoriesProvider).value ?? const <Category>[];
    final nameError = _nameError(existing);
    return UnsavedChangesScope(
      dirty: _name.text.trim().isNotEmpty,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add category', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                key: const Key('new-category-name'),
                controller: _name,
                autofocus: true,
                maxLength: kCategoryNameMaxLength,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Pet care, School fees',
                  errorText: _tried || _name.text.isNotEmpty ? nameError : null,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<TxnType>(
                key: const Key('new-category-kind'),
                showSelectedIcon: false,
                segments: [
                  for (final k in [TxnType.expense, TxnType.income])
                    ButtonSegment(value: k, icon: Icon(k.icon, size: 18), label: Text(k.label)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                'Ventrafin picks an icon and colour from the name. Change them afterwards by opening the category.',
                style: theme.textTheme.bodySmall,
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
                    key: const Key('new-category-save'),
                    onPressed: _saving ? null : () => _save(existing),
                    icon: _saving
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: const Text('Add category'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rename one category and pick its icon and colour; Save writes all three.
/// An active category can be archived from here too.
class CategoryEditSheet extends ConsumerStatefulWidget {
  const CategoryEditSheet({super.key, required this.category});

  final Category category;

  @override
  ConsumerState<CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<CategoryEditSheet> {
  late final _name = TextEditingController(text: widget.category.name);
  late String _iconKey = widget.category.iconKey;
  late String _colorHex = toHexColor(widget.category.color);
  bool _saving = false;
  String? _error;

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

  bool get _changed =>
      _name.text.trim() != widget.category.name ||
      _iconKey != widget.category.iconKey ||
      _colorHex != toHexColor(widget.category.color);

  String? get _nameError => categoryNameError(
        _name.text,
        kind: widget.category.kind,
        existing: ref.read(categoriesProvider).value ?? const <Category>[],
        exceptId: widget.category.id,
      );

  Future<void> _archive() async {
    final category = widget.category;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${category.name}?'),
        content: const Text(
          'It disappears from the category pickers and auto-categorization stops using it. '
          'Its past transactions keep it, and you can restore it any time.',
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
      await ref.read(repositoryProvider).setCategoryArchived(category.id, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Not archived. ${describeError(e)}';
      });
      return;
    }
    ref.read(revisionsProvider.notifier).bump(['categories']);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    messenger?.showSnackBar(SnackBar(content: Text('Archived ${category.name}')));
  }

  Future<void> _save() async {
    if (_nameError != null) return;
    if (!ref.read(isOnlineProvider)) {
      setState(() => _error = "There's no internet connection. Nothing was changed.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .updateCategory(widget.category.id, name: _name.text.trim(), iconKey: _iconKey, colorHex: _colorHex);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Not saved. ${describeError(e)}';
      });
      return;
    }
    ref.read(revisionsProvider.notifier).bump(['categories']);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    final newName = _name.text.trim();
    messenger?.showSnackBar(SnackBar(
      content: Text(newName == widget.category.name
          ? '${widget.category.name} updated'
          : '${widget.category.name} renamed to $newName'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = parseHexColor(_colorHex);
    // A colour from outside the palette (set some other way, e.g. by the web
    // app) stays selectable, first in the row.
    final swatches = [
      if (!kCategoryPaletteHex.contains(_colorHexOriginal)) _colorHexOriginal,
      ...kCategoryPaletteHex,
    ];

    final nameError = _nameError;

    // Lifted above the on-screen keyboard while the name is being typed.
    return UnsavedChangesScope(
      dirty: _changed,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: ColorIconCircle(icon: categoryIconFor(_iconKey), color: color, size: 44),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('category-name'),
                      controller: _name,
                      maxLength: kCategoryNameMaxLength,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: '${widget.category.kind.label} category name',
                        errorText: nameError,
                        counterText: '',
                      ),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Colour', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final hex in swatches)
                        _Swatch(
                          key: Key('color-$hex'),
                          color: parseHexColor(hex),
                          selected: hex == _colorHex,
                          onTap: () => setState(() => _colorHex = hex),
                        ),
                    ]),
                    for (final group in kCategoryIconGroups) ...[
                      const SizedBox(height: 12),
                      Text(group.name, style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final def in group.icons)
                          _IconChoice(
                            key: Key('icon-${def.key}'),
                            def: def,
                            color: color,
                            selected: def.key == _iconKey,
                            onTap: () => setState(() => _iconKey = def.key),
                          ),
                      ]),
                    ],
                  ]),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.paddingOf(context).bottom),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
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
                        key: const Key('category-save'),
                        onPressed: _saving || !_changed || nameError != null ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: const Text('Save'),
                      ),
                    ),
                  ]),
                  if (!widget.category.archived)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('category-archive'),
                        onPressed: _saving ? null : _archive,
                        icon: const Icon(Icons.archive_outlined, size: 18),
                        label: const Text('Archive this category'),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _colorHexOriginal => toHexColor(widget.category.color);
}

class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : Colors.black12,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected ? Icon(Icons.check, size: 20, color: foregroundOn(color)) : null,
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    super.key,
    required this.def,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final CategoryIconDef def;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: def.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? color : scheme.surfaceContainerHigh,
            shape: BoxShape.circle,
            border: selected ? Border.all(color: scheme.onSurface, width: 2) : null,
          ),
          child: Icon(def.icon, size: 24, color: selected ? foregroundOn(color) : scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
