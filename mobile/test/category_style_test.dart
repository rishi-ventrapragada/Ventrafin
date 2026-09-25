import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/category_style.dart';
import 'package:ventrafin/core/merchant.dart';
import 'package:ventrafin/data/models.dart';

/// Tests run with the package root (mobile/) as the working directory.
final _sharedJson = jsonDecode(File('../shared/category-style.json').readAsStringSync()) as Map<String, dynamic>;

/// The newest migration that contains [marker], so a later migration that
/// changes the list is the one compared against.
String _latestMigrationWith(String marker) {
  final files = Directory('../supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.reversed.map((f) => f.readAsStringSync()).firstWhere((s) => s.contains(marker));
}

List<String> _quoted(String sql) =>
    RegExp(r"'([^']*)'").allMatches(sql).map((m) => m.group(1)!).toList();

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('curated icon set stays in step with /shared and the database', () {
    test('Dart groups, keys and labels match shared/category-style.json', () {
      final groups = (_sharedJson['iconGroups'] as List).cast<Map<String, dynamic>>();
      expect(kCategoryIconGroups.map((g) => g.name), groups.map((g) => g['name']));
      for (var i = 0; i < groups.length; i++) {
        final icons = (groups[i]['icons'] as List).cast<Map<String, dynamic>>();
        expect(kCategoryIconGroups[i].icons.map((d) => d.key), icons.map((d) => d['key']),
            reason: 'group ${groups[i]['name']}');
        expect(kCategoryIconGroups[i].icons.map((d) => d.label), icons.map((d) => d['label']));
      }
    });

    test('icon keys are unique and equal the categories_icon_check constraint', () {
      final keys = [for (final g in kCategoryIconGroups) ...g.icons.map((d) => d.key)];
      expect(keys.toSet(), hasLength(keys.length), reason: 'no duplicates');

      final sql = _latestMigrationWith('categories_icon_check check');
      final body = sql.substring(sql.indexOf('categories_icon_check check'));
      final list = body.substring(body.indexOf('('), body.indexOf('));'));
      expect(_quoted(list).toSet(), keys.toSet());
    });

    test('palette equals the shared file and private.category_palette(), in order', () {
      expect(kCategoryPaletteHex, (_sharedJson['palette'] as List).cast<String>());

      final sql = _latestMigrationWith('function private.category_palette()');
      final body = sql.substring(sql.indexOf('function private.category_palette()'));
      final array = body.substring(body.indexOf('array['), body.indexOf(']::text[]'));
      expect(_quoted(array), kCategoryPaletteHex);
      expect(kCategoryPaletteHex.toSet(), hasLength(kCategoryPaletteHex.length));
    });

    test('the default icon is in the set', () {
      expect(kCategoryIconsByKey, contains(kDefaultCategoryIconKey));
      expect(_sharedJson['defaultIcon'], kDefaultCategoryIconKey);
    });
  });

  group('icons and colours', () {
    test('unknown or missing keys fall back to the tag icon', () {
      expect(categoryIconFor('restaurant'), Icons.restaurant);
      expect(categoryIconFor('not_a_real_icon'), Icons.label);
      expect(categoryIconFor(null), Icons.label);
    });

    test('Category.fromRow reads the icon key', () {
      final c = Category.fromRow(
          {'id': 'x', 'name': 'Fuel', 'kind': 'expense', 'color': '#6D4C41', 'archived': false, 'icon': 'local_gas_station'});
      expect(c.iconKey, 'local_gas_station');
      expect(toHexColor(c.color), '#6D4C41');
    });

    test('every palette colour round-trips through parse/toHex', () {
      for (final hex in kCategoryPaletteHex) {
        expect(toHexColor(parseHexColor(hex)), hex);
      }
    });

    test('glyphs on every palette colour reach 3:1 contrast (WCAG non-text)', () {
      for (final hex in kCategoryPaletteHex) {
        final bg = parseHexColor(hex);
        final fg = Color.alphaBlend(foregroundOn(bg), bg);
        expect(_contrast(fg, bg), greaterThanOrEqualTo(3), reason: hex);
      }
    });

    test('category names written in their colour are readable on white (4.5:1)', () {
      for (final hex in kCategoryPaletteHex) {
        expect(_contrast(readableTextColor(parseHexColor(hex)), Colors.white), greaterThanOrEqualTo(4.5),
            reason: hex);
      }
    });
  });

  group('merchant letter badges', () {
    test('examples in the shared file', () {
      final examples = ((_sharedJson['merchantBadge'] as Map)['examples'] as List).cast<Map<String, dynamic>>();
      for (final e in examples) {
        final description = e['description'] as String;
        expect(merchantKey(description), e['key'], reason: description);
        expect(merchantBadgeFor(description)?.letter, e['letter'], reason: description);
      }
    });

    test('filler words match the shared file', () {
      expect(kMerchantFillerWords,
          ((_sharedJson['merchantBadge'] as Map)['fillerWords'] as List).cast<String>().toSet());
    });

    test('same merchant, same letter and colour, however the bank writes it', () {
      final a = merchantBadgeFor('Swiggy dinner');
      final b = merchantBadgeFor('UPI/SWIGGY/4471023@icici');
      final c = merchantBadgeFor('Paid to swiggy order #88');
      expect(a, isNotNull);
      expect(b, a);
      expect(c, a);
      expect(a!.letter, 'S');
      expect(kCategoryPaletteHex, contains(a.colorHex));
    });

    test('different merchants usually get different colours', () {
      final colours = {
        for (final m in ['Swiggy', 'Zomato', 'DMart', 'Apollo', 'Uber', 'Airtel', 'Amazon', 'Ramesh'])
          merchantBadgeFor(m)!.colorHex,
      };
      expect(colours.length, greaterThanOrEqualTo(5));
    });

    test('no merchant word: no badge', () {
      expect(merchantBadgeFor(''), isNull);
      expect(merchantBadgeFor('4471023'), isNull);
      expect(merchantBadgeFor('UPI / paid to 998877'), isNull);
    });

    test('non-Latin names keep their vowel signs', () {
      expect(merchantKey('दूध वाला'), 'दूध');
      expect(merchantBadgeFor('दूध वाला')!.letter, 'द');
    });

    test('FNV-1a matches the published test vectors (so the web app can match it)', () {
      expect(fnv1a32(''), 0x811c9dc5);
      expect(fnv1a32('a'), 0xe40c292c);
      expect(fnv1a32('foobar'), 0xbf9cf968);
    });
  });
}
