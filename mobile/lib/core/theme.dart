import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme_tokens.dart';

export 'theme_tokens.dart';

/// Light mode only (PRD § 4.8). Six themes, all from /shared/theme-tokens.json
/// (DECISIONS.md D22):
///  * the app bar is the theme's `brand` colour with `onBrand` on it;
///  * buttons, links, switches and selections use `primary`, which is always
///    dark enough for text on white (the yellow themes' brand isn't);
///  * cards and sheets are white on the theme's `page` colour, so category
///    colours sit on the same surfaces in every theme and on both apps.
ThemeData buildAppTheme(ThemeTokens t) {
  final scheme = ColorScheme.fromSeed(seedColor: t.primary, brightness: Brightness.light).copyWith(
    primary: t.primary,
    onPrimary: Colors.white,
    primaryContainer: t.primarySoft,
    onPrimaryContainer: t.primaryHover,
    secondary: t.accent,
    onSecondary: t.onAccent,
    secondaryContainer: t.accentSoft,
    onSecondaryContainer: const Color(0xFF1F1F1F),
    surface: t.page,
    surfaceContainerLowest: kCardColor,
    surfaceContainerLow: kCardColor,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: t.page,
    extensions: [AppPalette(t)],
    // Dense, Excel-like layouts (DECISIONS.md D7), with standard tap targets.
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(backgroundColor: t.brand, foregroundColor: t.onBrand, centerTitle: false),
    cardTheme: const CardThemeData(color: kCardColor, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: kCardColor, surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(backgroundColor: kCardColor, surfaceTintColor: Colors.transparent),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    listTileTheme: const ListTileThemeData(dense: true),
    // Solid primary, like the other main buttons (M3's default is the pale
    // primaryContainer, which here is primarySoft).
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: kCardColor,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.accentSoft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Dark status-bar icons on a transparent bar, for screens without an app
/// bar (sign-in, splash, lock): their page colour is near-white in every
/// theme. Screens with an app bar get icons to suit its brand colour from
/// the AppBar itself (dark on the yellow themes, light on the others).
const SystemUiOverlayStyle kDarkStatusBarIcons = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark, // Android
  statusBarBrightness: Brightness.light, // iOS naming; kept for completeness
);

/// The Ocean theme, used before the profile has loaded and in tests.
ThemeData buildOceanTheme() => buildAppTheme(themeTokensFor('ocean'));

/// The current theme's tokens, for the few places that need more than the
/// ColorScheme (the app bar's colours, the surfaces category circles sit on).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(this.tokens);

  final ThemeTokens tokens;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? AppPalette(themeTokensFor(kDefaultThemeId));

  @override
  AppPalette copyWith({ThemeTokens? tokens}) => AppPalette(tokens ?? this.tokens);

  @override
  AppPalette lerp(AppPalette? other, double t) => t < 0.5 || other == null ? this : other;
}
