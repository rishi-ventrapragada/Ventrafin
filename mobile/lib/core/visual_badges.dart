import 'package:flutter/material.dart';

import '../data/models.dart';
import 'category_style.dart';
import 'merchant.dart';
import 'theme.dart';

/// Icons for the fixed enums. Kept out of models.dart so the data layer
/// stays about data.
extension AccountTypeVisuals on AccountType {
  IconData get icon => switch (this) {
        AccountType.cash => Icons.payments_outlined,
        AccountType.bank => Icons.account_balance,
        AccountType.credit => Icons.credit_card,
      };

  Color get color => switch (this) {
        AccountType.cash => const Color(0xFF2E7D32),
        AccountType.bank => const Color(0xFF1565C0),
        AccountType.credit => const Color(0xFF6A1B9A),
      };
}

extension PaymentMethodVisuals on PaymentMethod {
  IconData get icon => switch (this) {
        PaymentMethod.cash => Icons.payments_outlined,
        PaymentMethod.upi => Icons.qr_code_2,
        PaymentMethod.debit => Icons.atm,
        PaymentMethod.card => Icons.credit_card,
      };
}

extension TxnTypeVisuals on TxnType {
  IconData get icon => switch (this) {
        TxnType.expense => Icons.remove_circle_outline,
        TxnType.income => Icons.add_circle_outline,
        TxnType.transfer => Icons.swap_horiz,
      };
}

extension CategoryVisuals on Category {
  IconData get icon => categoryIconFor(iconKey);
}

/// A category's icon in a filled circle of its colour.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 32});

  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) => ColorIconCircle(
        icon: category.icon,
        color: category.color,
        size: size,
        semanticLabel: category.name,
      );
}

/// Filled circle with a readable glyph (white, or dark on pale colours).
class ColorIconCircle extends StatelessWidget {
  const ColorIconCircle({super.key, required this.icon, required this.color, this.size = 32, this.semanticLabel});

  final IconData icon;
  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.58, color: foregroundOn(color), semanticLabel: semanticLabel),
    );
  }
}

/// Outlined (not filled) circle: used for "no category" states, so they
/// can't be mistaken for a real category at a glance.
class OutlinedIconCircle extends StatelessWidget {
  const OutlinedIconCircle({
    super.key,
    required this.icon,
    required this.color,
    this.size = 32,
    this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: size >= 28 ? 2 : 1.5),
      ),
      child: Icon(icon, size: size * 0.55, color: color, semanticLabel: semanticLabel),
    );
  }
}

/// Uncategorized: an amber question mark in an outlined circle.
class UncategorizedAvatar extends StatelessWidget {
  const UncategorizedAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => OutlinedIconCircle(
        key: const Key('uncategorized-avatar'),
        icon: Icons.question_mark,
        color: kUncategorizedColor,
        size: size,
        semanticLabel: 'Uncategorized',
      );
}

class TransferAvatar extends StatelessWidget {
  const TransferAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => OutlinedIconCircle(
        icon: Icons.swap_horiz,
        color: kTransferColor,
        size: size,
        semanticLabel: 'Transfer',
      );
}

/// "Auto" in the category picker: let the database choose.
class AutoCategoryAvatar extends StatelessWidget {
  const AutoCategoryAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => OutlinedIconCircle(
        icon: Icons.auto_awesome,
        color: Theme.of(context).colorScheme.primary,
        size: size,
        semanticLabel: 'Auto category',
      );
}

/// The leading visual of a transaction: its category, Uncategorized, or
/// Transfer.
class TxnAvatar extends StatelessWidget {
  const TxnAvatar({super.key, required this.txn, required this.category, this.size = 32});

  final Txn txn;

  /// Null when the transaction has no category (or it hasn't loaded yet).
  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (txn.type == TxnType.transfer) return TransferAvatar(size: size);
    if (txn.categoryId == null) return UncategorizedAvatar(size: size);
    final c = category;
    // Category row not loaded yet (e.g. just auto-created): neutral circle.
    if (c == null) return ColorIconCircle(icon: Icons.label, color: Colors.grey.shade400, size: size);
    return CategoryAvatar(category: c, size: size);
  }
}

/// Small rounded-square letter badge for the merchant in a description
/// (see core/merchant.dart). Renders nothing when there is no merchant word.
class MerchantBadge extends StatelessWidget {
  const MerchantBadge({super.key, required this.description, this.size = 16});

  final String description;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = merchantBadgeFor(description);
    if (badge == null) return const SizedBox.shrink();
    final color = parseHexColor(badge.colorHex);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Text(
        badge.letter,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: size * 0.62,
          height: 1,
          fontWeight: FontWeight.w700,
          color: readableTextColor(color),
        ),
      ),
    );
  }
}

/// Account type icon in a tinted circle.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.type, this.size = 32});

  final AccountType type;
  final double size;

  @override
  Widget build(BuildContext context) => ColorIconCircle(
        icon: type.icon,
        color: type.color,
        size: size,
        semanticLabel: type.label,
      );
}
