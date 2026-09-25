import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_style.dart';
import '../../core/errors.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Categories with their icons and colours. Tap one to rename it or restyle
/// it from the curated set. Updates live, e.g. when auto-categorization
/// creates one. (Adding and archiving come with the categorization phase.)
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: switch (categories) {
        AsyncValue(:final value?) => ListView(children: [
            for (final kind in [TxnType.expense, TxnType.income]) ...[
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('${kind.label} categories', style: theme.textTheme.labelLarge),
              ),
              for (final c in _sorted(value.where((c) => c.kind == kind)))
                ListTile(
                  key: Key('category-${c.id}'),
                  leading: CategoryAvatar(category: c, size: 34),
                  title: Text(c.name),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (c.archived)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('archived', style: theme.textTheme.labelSmall),
                      ),
                    const Icon(Icons.edit_outlined, size: 20),
                  ]),
                  onTap: () => showCategoryEditor(context, c),
                ),
            ],
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Tap a category to rename it or change its icon and colour. '
                  'Renaming keeps its automatic matches: if Food becomes "Khana", Swiggy still goes there. '
                  'Adding and archiving categories are coming in a later update.'),
            ),
          ]),
        AsyncValue(:final error?) => Center(child: Text('Could not load categories: ${describeError(error)}')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  static List<Category> _sorted(Iterable<Category> cs) =>
      cs.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

Future<void> showCategoryEditor(BuildContext context, Category category) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => CategoryEditSheet(category: category),
  );
}

/// Rename one category and pick its icon and colour; Save writes all three.
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
    return Padding(
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
                      onPressed: _saving ? null : () => Navigator.pop(context),
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
              ]),
            ),
          ],
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
