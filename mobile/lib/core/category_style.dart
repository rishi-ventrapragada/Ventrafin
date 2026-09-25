import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Curated category icons and colours (DECISIONS.md D13).
///
/// The database stores an icon KEY per category (`categories.icon`), never an
/// image. Keys are Google Material Symbols names, so the web app can render
/// the same icon from the Material Symbols font. This file mirrors
/// /shared/category-style.json and the database's `categories_icon_check`
/// constraint; test/category_style_test.dart keeps all three in step.

@immutable
class CategoryIconDef {
  const CategoryIconDef(this.key, this.icon, this.label);

  /// Material Symbols name, as stored in `categories.icon`.
  final String key;
  final IconData icon;

  /// Short name shown as a tooltip / for screen readers.
  final String label;
}

@immutable
class CategoryIconGroup {
  const CategoryIconGroup(this.name, this.icons);
  final String name;
  final List<CategoryIconDef> icons;
}

const String kDefaultCategoryIconKey = 'label';

/// In picker order. Every `IconData` is a const `Icons.*` reference so the
/// icon font is still tree-shaken in release builds.
const List<CategoryIconGroup> kCategoryIconGroups = [
  CategoryIconGroup('General', [
    CategoryIconDef('label', Icons.label, 'Tag'),
    CategoryIconDef('more_horiz', Icons.more_horiz, 'Other'),
  ]),
  CategoryIconGroup('Food & home', [
    CategoryIconDef('restaurant', Icons.restaurant, 'Food'),
    CategoryIconDef('local_cafe', Icons.local_cafe, 'Tea & coffee'),
    CategoryIconDef('fastfood', Icons.fastfood, 'Snacks'),
    CategoryIconDef('bakery_dining', Icons.bakery_dining, 'Bakery'),
    CategoryIconDef('shopping_cart', Icons.shopping_cart, 'Groceries'),
    CategoryIconDef('house', Icons.house, 'Home & rent'),
    CategoryIconDef('cleaning_services', Icons.cleaning_services, 'Cleaning & help'),
    CategoryIconDef('local_laundry_service', Icons.local_laundry_service, 'Laundry'),
    CategoryIconDef('handyman', Icons.handyman, 'Repairs'),
    CategoryIconDef('pets', Icons.pets, 'Pets'),
  ]),
  CategoryIconGroup('Bills & utilities', [
    CategoryIconDef('receipt_long', Icons.receipt_long, 'Bills'),
    CategoryIconDef('bolt', Icons.bolt, 'Electricity'),
    CategoryIconDef('water_drop', Icons.water_drop, 'Water'),
    CategoryIconDef('propane_tank', Icons.propane_tank, 'Cooking gas'),
    CategoryIconDef('smartphone', Icons.smartphone, 'Mobile'),
    CategoryIconDef('wifi', Icons.wifi, 'Internet'),
    CategoryIconDef('tv', Icons.tv, 'TV / DTH'),
    CategoryIconDef('event_repeat', Icons.event_repeat, 'EMI'),
    CategoryIconDef('request_quote', Icons.request_quote, 'Tax & fees'),
  ]),
  CategoryIconGroup('Transport & travel', [
    CategoryIconDef('local_taxi', Icons.local_taxi, 'Cab & auto'),
    CategoryIconDef('directions_car', Icons.directions_car, 'Car'),
    CategoryIconDef('two_wheeler', Icons.two_wheeler, 'Two-wheeler'),
    CategoryIconDef('directions_bus', Icons.directions_bus, 'Bus'),
    CategoryIconDef('train', Icons.train, 'Train & metro'),
    CategoryIconDef('local_gas_station', Icons.local_gas_station, 'Fuel'),
    CategoryIconDef('local_parking', Icons.local_parking, 'Parking'),
    CategoryIconDef('flight', Icons.flight, 'Flights'),
    CategoryIconDef('luggage', Icons.luggage, 'Trips'),
  ]),
  CategoryIconGroup('Health & family', [
    CategoryIconDef('local_hospital', Icons.local_hospital, 'Medical'),
    CategoryIconDef('medication', Icons.medication, 'Medicines'),
    CategoryIconDef('local_pharmacy', Icons.local_pharmacy, 'Pharmacy'),
    CategoryIconDef('fitness_center', Icons.fitness_center, 'Fitness'),
    CategoryIconDef('spa', Icons.spa, 'Wellness'),
    CategoryIconDef('child_care', Icons.child_care, 'Children'),
    CategoryIconDef('elderly', Icons.elderly, 'Elders'),
    CategoryIconDef('family_restroom', Icons.family_restroom, 'Family'),
    CategoryIconDef('school', Icons.school, 'Education'),
    CategoryIconDef('menu_book', Icons.menu_book, 'Books'),
  ]),
  CategoryIconGroup('Shopping & leisure', [
    CategoryIconDef('shopping_bag', Icons.shopping_bag, 'Shopping'),
    CategoryIconDef('checkroom', Icons.checkroom, 'Clothes'),
    CategoryIconDef('content_cut', Icons.content_cut, 'Salon'),
    CategoryIconDef('card_giftcard', Icons.card_giftcard, 'Gifts'),
    CategoryIconDef('celebration', Icons.celebration, 'Festivals'),
    CategoryIconDef('movie', Icons.movie, 'Entertainment'),
    CategoryIconDef('sports_esports', Icons.sports_esports, 'Games'),
    CategoryIconDef('sports_cricket', Icons.sports_cricket, 'Sports'),
    CategoryIconDef('temple_hindu', Icons.temple_hindu, 'Temple & pooja'),
    CategoryIconDef('volunteer_activism', Icons.volunteer_activism, 'Donations'),
  ]),
  CategoryIconGroup('Money', [
    CategoryIconDef('account_balance_wallet', Icons.account_balance_wallet, 'Salary'),
    CategoryIconDef('currency_rupee', Icons.currency_rupee, 'Money'),
    CategoryIconDef('percent', Icons.percent, 'Interest'),
    CategoryIconDef('savings', Icons.savings, 'Savings'),
    CategoryIconDef('trending_up', Icons.trending_up, 'Investments'),
    CategoryIconDef('undo', Icons.undo, 'Refund'),
    CategoryIconDef('redeem', Icons.redeem, 'Cashback & rewards'),
    CategoryIconDef('work', Icons.work, 'Business'),
    CategoryIconDef('sell', Icons.sell, 'Sales'),
    CategoryIconDef('shield', Icons.shield, 'Insurance'),
    CategoryIconDef('real_estate_agent', Icons.real_estate_agent, 'Rent received'),
  ]),
];

final Map<String, CategoryIconDef> kCategoryIconsByKey = {
  for (final g in kCategoryIconGroups)
    for (final d in g.icons) d.key: d,
};

/// The icon for a stored key. An unknown key (say, one added by a newer web
/// app) falls back to the plain tag rather than failing.
IconData categoryIconFor(String? key) => kCategoryIconsByKey[key]?.icon ?? Icons.label;

/// Colour picker palette, in picker order. Same list, same order as the
/// database's `private.category_palette()`.
const List<String> kCategoryPaletteHex = [
  '#E53935', '#BF360C', '#FFAB91', '#FB8C00', '#FDD835', '#C0CA33',
  '#AED581', '#43A047', '#2E7D32', '#0097A7', '#4FC3F7', '#1E88E5',
  '#1565C0', '#3949AB', '#B39DDB', '#8E24AA', '#AD1457', '#EC407A',
  '#6D4C41', '#A1887F', '#546E7A', '#78909C', '#9E9E9E', '#263238',
];

/// `#RRGGBB` (upper case) for a colour.
String toHexColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// WCAG contrast ratio between two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The dark glyph colour: 87 % black, drawn over the circle.
const Color kDarkGlyph = Color(0xDD000000);

/// White or near-black, whichever has more contrast on [background]; white
/// keeps near-ties (within 10 %, e.g. red #E53935, where both are about
/// 4.4:1). Every palette colour gets a glyph at 4.2:1 or better. Same rule
/// as the web app; /shared/category-style.json lists the result for every
/// palette colour and both apps' tests check it (DECISIONS.md D20).
Color foregroundOn(Color background) {
  final whiteContrast = contrastRatio(Colors.white, background);
  final darkContrast = contrastRatio(Color.alphaBlend(kDarkGlyph, background), background);
  return whiteContrast * 1.1 >= darkContrast ? Colors.white : kDarkGlyph;
}

/// A darker shade of [c] that reaches [minRatio] (4.5:1 unless given) on
/// [surface] (white unless given): for text or glyphs drawn in a category's
/// colour, since pale palette colours are unreadable as text otherwise.
Color readableTextColor(Color c, {Color surface = Colors.white, double minRatio = 4.5}) {
  var out = c;
  for (var i = 0; i < 6 && contrastRatio(out, surface) < minRatio; i++) {
    out = Color.lerp(out, Colors.black, 0.2)!;
  }
  return out;
}

/// The glyph and ring colour of an outlined circle (Uncategorized, Transfer,
/// Auto): a shade of [color] that reaches 4.5:1 on the circle's 10 % tint
/// over each of [surfaces] (DECISIONS.md D20).
Color outlinedInkFor(Color color, Iterable<Color> surfaces) {
  final tints = [for (final s in surfaces) Color.alphaBlend(color.withValues(alpha: 0.10), s)];
  var out = color;
  for (var i = 0; i < 8 && tints.any((t) => contrastRatio(out, t) < 4.5); i++) {
    out = Color.lerp(out, Colors.black, 0.2)!;
  }
  return out;
}

/// Below this contrast against a surface it sits on, a filled circle's edge
/// gets lost (yellow on white is 1.4:1), so it gets an outline.
const double kCircleEdgeMinContrast = 1.5;

/// The outline for a filled circle of [fill] shown on any of [surfaces], or
/// null when the fill stands out from all of them: a darker shade of the
/// fill at 3:1 or better against every surface (DECISIONS.md D20).
Color? circleEdgeFor(Color fill, Iterable<Color> surfaces) {
  if (surfaces.every((s) => contrastRatio(fill, s) >= kCircleEdgeMinContrast)) return null;
  var out = fill;
  for (var i = 0; i < 8 && surfaces.any((s) => contrastRatio(out, s) < 3); i++) {
    out = Color.lerp(out, Colors.black, 0.2)!;
  }
  return out;
}
