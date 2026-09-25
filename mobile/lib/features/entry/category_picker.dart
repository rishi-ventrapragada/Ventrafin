import 'package:flutter/material.dart';

import '../../core/visual_badges.dart';
import '../../data/models.dart';

/// What the picker returned. Wraps the id so "Auto" (null) can be told
/// apart from dismissing the sheet (the whole result is null).
@immutable
class CategoryChoice {
  const CategoryChoice(this.id);

  /// Null = Auto (let the database categorize).
  final String? id;
}

/// Bottom sheet with every active category of [kind] as an icon tile, so a
/// category can be found by its picture and colour, not only its name.
/// Archived categories are left out, except the current one ([selectedId])
/// of an existing entry, which shows as "Name (archived)".
Future<CategoryChoice?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
  required TxnType kind,
  required String? selectedId,
  bool allowAuto = true,
}) {
  final options = categories.where((c) => c.kind == kind && (!c.archived || c.id == selectedId)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return showModalBottomSheet<CategoryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${kind.label} category', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // Fixed-width tiles whose height follows their content, so a
              // two-line name or a large system font size never overflows.
              LayoutBuilder(builder: (context, constraints) {
                const spacing = 4.0;
                final width = (constraints.maxWidth - spacing * 3) / 4;
                Widget sized(Widget tile) => SizedBox(width: width, child: tile);
                return Wrap(spacing: spacing, runSpacing: spacing, children: [
                  if (allowAuto)
                    sized(_Tile(
                      key: const Key('category-option-auto'),
                      avatar: const AutoCategoryAvatar(size: 40),
                      label: 'Auto',
                      selected: selectedId == null,
                      onTap: () => Navigator.pop(context, const CategoryChoice(null)),
                    )),
                  for (final c in options)
                    sized(_Tile(
                      key: Key('category-option-${c.id}'),
                      avatar: CategoryAvatar(category: c, size: 40),
                      // Only the current value of an existing entry can be archived here.
                      label: c.archived ? '${c.name} (archived)' : c.name,
                      selected: c.id == selectedId,
                      onTap: () => Navigator.pop(context, CategoryChoice(c.id)),
                    )),
                ]);
              }),
              if (allowAuto)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Auto: Ventrafin picks the category from the description.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.avatar, required this.label, required this.selected, required this.onTap});

  final Widget avatar;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: selected ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
