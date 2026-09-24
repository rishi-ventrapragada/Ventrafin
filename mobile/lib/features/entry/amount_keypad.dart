import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// On-screen number keypad for the amount (PRD § 4.2: keypad first). Using
/// our own keys means no system keyboard, no locale decimal-comma issues and
/// no way to type letters. Emits '0'-'9', '.', 'back'; [onDone] moves on to
/// the next field.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey, required this.onDone, this.doneLabel = 'Next'});

  final ValueChanged<String> onKey;
  final VoidCallback onDone;
  final String doneLabel;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', 'back'],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    for (final row in _rows)
                      Row(children: [for (final k in row) Expanded(child: _Key(k, onKey))]),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: SizedBox(
                    height: 4 * 52 - 6,
                    child: FilledButton(
                      key: const Key('keypad-done'),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: onDone,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [const Icon(Icons.arrow_forward), Text(doneLabel)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.value, this.onKey);

  final String value;
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final isBack = value == 'back';
    return Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        height: 46,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: Key('keypad-$value'),
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              HapticFeedback.selectionClick();
              onKey(value);
            },
            onLongPress: isBack ? () => onKey('clear') : null,
            child: Center(
              child: isBack
                  ? const Icon(Icons.backspace_outlined, semanticLabel: 'Delete')
                  : Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
    );
  }
}
