import 'package:flutter/material.dart';

/// The "Ocean" theme (blue / teal), light mode only (PRD § 4.8). The full set
/// of six themes, shared with the web app via /shared/theme-tokens.json,
/// arrives in phase 7. Until then these two colours are the only source.
const Color kOceanPrimary = Color(0xFF1565C0);
const Color kOceanAccent = Color(0xFF00897B);

/// Semantic colours for amounts.
const Color kExpenseColor = Color(0xFFC62828);
const Color kIncomeColor = Color(0xFF2E7D32);
const Color kTransferColor = Color(0xFF546E7A);
const Color kUncategorizedColor = Color(0xFFB26A00);

ThemeData buildOceanTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kOceanPrimary,
    primary: kOceanPrimary,
    secondary: kOceanAccent,
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // Dense, Excel-like layouts (DECISIONS.md D7), with standard tap targets.
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: false,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    listTileTheme: const ListTileThemeData(dense: true),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
