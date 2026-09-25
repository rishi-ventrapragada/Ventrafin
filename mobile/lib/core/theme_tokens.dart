import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'theme_tokens.g.dart';

export 'theme_tokens.g.dart';

/// One colour theme from /shared/theme-tokens.json (PRD § 4.8, DECISIONS.md
/// D22). The values live in theme_tokens.g.dart, generated from that file by
/// `dart run tool/gen_theme_tokens.dart`; test/theme_test.dart fails if the
/// two drift apart.
@immutable
class ThemeTokens {
  const ThemeTokens({
    required this.id,
    required this.name,
    required this.description,
    required this.brand,
    required this.onBrand,
    required this.brandIndicator,
    required this.primary,
    required this.primaryHover,
    required this.primarySoft,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.page,
  });

  /// Stored in `profiles.theme`.
  final String id;
  final String name;

  /// "Blue and teal".
  final String description;

  /// The app bar, with [onBrand] text and icons on it.
  final Color brand;
  final Color onBrand;

  /// Marks the current section on the brand colour (the web sidebar).
  final Color brandIndicator;

  /// Buttons, links, switches and selected states. Readable as text on white
  /// and on [page], and under white text.
  final Color primary;
  final Color primaryHover;

  /// Selected / highlighted rows and tiles.
  final Color primarySoft;

  final Color accent;
  final Color onAccent;

  /// The bottom navigation bar's indicator.
  final Color accentSoft;

  /// Behind the cards (cards are white).
  final Color page;

  /// Every surface a category circle can sit on in this theme.
  List<Color> get surfaces => [kCardColor, page, primarySoft];
}

/// The theme stored under [id], or the default for an unknown id (say, one
/// added by a newer web app).
ThemeTokens themeTokensFor(String? id) =>
    kThemes.firstWhere((t) => t.id == id, orElse: () => kThemes.firstWhere((t) => t.id == kDefaultThemeId));
