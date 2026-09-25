import 'dart:async';

import 'package:flutter/material.dart';

/// "Discard changes?" before throwing away what was typed. True = discard.
/// "Keep editing" is the default (focused) answer, and tapping outside or
/// pressing back also keeps editing.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard changes?'),
      content: const Text("What you typed hasn't been saved."),
      actions: [
        TextButton(
          key: const Key('discard-changes'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
        FilledButton(
          key: const Key('keep-editing'),
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep editing'),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Guards a form against losing unsaved changes. While [dirty], leaving it
/// asks "Discard changes?" first: the system back button, the app bar's
/// back/close button, a Cancel button that calls `Navigator.maybePop`, and
/// for a sheet opened with [showGuardedSheet] also tapping outside it or
/// dragging it down. An untouched form closes without asking.
///
/// Closing after a successful save uses `Navigator.pop` (or go_router's
/// `context.pop`), which never asks.
class UnsavedChangesScope extends StatelessWidget {
  const UnsavedChangesScope({super.key, required this.dirty, required this.child});

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

/// A modal bottom sheet whose drag-to-close also respects an
/// [UnsavedChangesScope] inside it. (Flutter's sheet closes itself with
/// `Navigator.pop` when dragged down, which skips PopScope; tapping outside
/// and the back button already go through it.)
Future<T?> showGuardedSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _GuardedSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    ),
  );
}

class _GuardedSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _GuardedSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.isScrollControlled,
    required super.showDragHandle,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
  });

  @override
  bool didPop(T? result) {
    // A drag that ends "closed" starts the sheet's closing animation and
    // then calls Navigator.pop. A pop from code (Save, Discard) arrives with
    // the sheet open. While a PopScope inside says "not now", undo the drag
    // and ask instead of closing.
    final status = controller?.status;
    final dragged = status == AnimationStatus.reverse || status == AnimationStatus.dismissed;
    if (dragged && popDisposition == RoutePopDisposition.doNotPop) {
      controller?.forward();
      // Asked once the navigator has finished handling this pop.
      scheduleMicrotask(() {
        if (isActive) onPopInvokedWithResult(false, result);
      });
      return false;
    }
    return super.didPop(result);
  }
}
