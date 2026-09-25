import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/category_style.dart';
import 'package:ventrafin/core/theme.dart';
import 'package:ventrafin/core/visual_badges.dart';
import 'package:ventrafin/data/models.dart';

import '../tool/gen_theme_tokens.dart' as gen;
import 'support/fake_repository.dart';

/// Tests run with the package root (mobile/) as the working directory.
Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
final _tokens = _json('../shared/theme-tokens.json');
final _style = _json('../shared/category-style.json');
final _palette = [for (final h in (_style['palette'] as List).cast<String>()) parseHexColor(h)];

/// The glyph actually drawn: white, or 87 % black over the circle.
Color _glyph(Color bg) => Color.alphaBlend(foregroundOn(bg), bg);

void main() {
  group('theme tokens stay in step with /shared/theme-tokens.json and the database', () {
    test('theme_tokens.g.dart is up to date (run: dart run tool/gen_theme_tokens.dart)', () {
      expect(File('lib/core/theme_tokens.g.dart').readAsStringSync(), gen.renderThemeTokens(_tokens));
    });

    test('theme ids equal the profiles_theme_check constraint, Ocean first and the default', () {
      final sql = File('../supabase/migrations/20260924154739_core_schema.sql').readAsStringSync();
      final check = RegExp(r"check \(theme in \(([^)]*)\)\)").firstMatch(sql)!.group(1)!;
      final ids = RegExp(r"'([a-z]+)'").allMatches(check).map((m) => m.group(1)).toList();
      expect(kThemes.map((t) => t.id), ids);
      expect(kDefaultThemeId, 'ocean');
      expect(themeTokensFor('no-such-theme').id, 'ocean');
    });
  });

  group('every theme is readable (WCAG 2.1 AA)', () {
    for (final t in kThemes) {
      test(t.name, () {
        // Text on the app bar / web sidebar, and the current-section marker.
        expect(contrastRatio(t.onBrand, t.brand), greaterThanOrEqualTo(4.5), reason: 'onBrand on brand');
        expect(contrastRatio(t.brandIndicator, t.brand), greaterThanOrEqualTo(3), reason: 'indicator on brand');
        // Buttons and links: text in primary on every surface, white text on primary.
        for (final s in t.surfaces) {
          expect(contrastRatio(t.primary, s), greaterThanOrEqualTo(4.5), reason: 'primary on ${toHexColor(s)}');
        }
        expect(contrastRatio(Colors.white, t.primary), greaterThanOrEqualTo(4.5), reason: 'white on primary');
        expect(contrastRatio(Colors.white, t.primaryHover), greaterThanOrEqualTo(4.5), reason: 'white on hover');
        expect(contrastRatio(t.onAccent, t.accent), greaterThanOrEqualTo(4.5), reason: 'onAccent on accent');
        // Amounts and the Uncategorized label on every surface.
        for (final s in t.surfaces) {
          for (final c in [kExpenseColor, kIncomeColor, kUncategorizedInkColor, kTransferColor]) {
            expect(contrastRatio(c, s), greaterThanOrEqualTo(4.5), reason: '${toHexColor(c)} on ${toHexColor(s)}');
          }
        }
      });
    }
  });

  group('category icons on every theme (palette × theme × surface)', () {
    test('glyph colour matches the shared table for every palette colour (so every built-in category)', () {
      final expected = ((_style['glyph'] as Map)['onPalette'] as Map).cast<String, String>();
      expect(expected.keys, kCategoryPaletteHex);
      for (final hex in kCategoryPaletteHex) {
        final got = foregroundOn(parseHexColor(hex)) == Colors.white ? 'white' : 'dark';
        expect(got, expected[hex], reason: hex);
      }
    });

    test('glyphs reach 4.2:1 on every palette colour (the circle is the same in every theme)', () {
      for (final c in _palette) {
        expect(contrastRatio(_glyph(c), c), greaterThanOrEqualTo(4.2), reason: toHexColor(c));
      }
    });

    for (final t in kThemes) {
      test('${t.name}: circles stand out from every surface, or get an outline that does', () {
        for (final c in _palette) {
          final edge = circleEdgeFor(c, t.surfaces);
          for (final s in t.surfaces) {
            if (edge == null) {
              expect(
                contrastRatio(c, s),
                greaterThanOrEqualTo(kCircleEdgeMinContrast),
                reason: '${toHexColor(c)} on ${toHexColor(s)}',
              );
            } else {
              expect(
                contrastRatio(edge, s),
                greaterThanOrEqualTo(3),
                reason: 'outline of ${toHexColor(c)} on ${toHexColor(s)}',
              );
            }
          }
        }
      });

      test('${t.name}: names in their category colour, and outlined looks, read at 4.5:1', () {
        for (final s in t.surfaces) {
          for (final c in _palette) {
            expect(
              contrastRatio(readableTextColor(c, surface: s), s),
              greaterThanOrEqualTo(4.5),
              reason: '${toHexColor(c)} as text on ${toHexColor(s)}',
            );
          }
          // Uncategorized "?", Transfer arrow, "Auto" sparkle (theme primary):
          // glyph in readableTextColor over a 10 % tint of the colour.
          for (final c in [kUncategorizedColor, kTransferColor, t.primary]) {
            final tint = Color.alphaBlend(c.withValues(alpha: 0.10), s);
            expect(
              contrastRatio(outlinedInkFor(c, t.surfaces), tint),
              greaterThanOrEqualTo(4.5),
              reason: 'outlined ${toHexColor(c)} on ${toHexColor(s)}',
            );
          }
        }
      });
    }

    test('merchant letters are readable on their own tinted badge (4.5:1)', () {
      for (final c in _palette) {
        final badge = Color.alphaBlend(c.withValues(alpha: 0.18), kCardColor);
        expect(
          contrastRatio(readableTextColor(c, surface: badge), badge),
          greaterThanOrEqualTo(4.5),
          reason: toHexColor(c),
        );
      }
    });

    test('only pale colours get an outline: yellow everywhere, light green on the highlight rows', () {
      final ocean = themeTokensFor('ocean');
      expect(circleEdgeFor(parseHexColor('#FDD835'), ocean.surfaces), isNotNull);
      expect(circleEdgeFor(parseHexColor('#AED581'), ocean.surfaces), isNotNull);
      expect(circleEdgeFor(parseHexColor('#1565C0'), ocean.surfaces), isNull);
      expect(circleEdgeFor(parseHexColor('#E53935'), ocean.surfaces), isNull);
    });
  });

  group('the theme applied to widgets', () {
    testWidgets('yellow theme: dark app bar text, readable primary buttons', (tester) async {
      final sunflower = themeTokensFor('sunflower');
      await pumpWithFakes(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('Bills')),
          body: TextButton(onPressed: () {}, child: const Text('Mark paid')),
        ),
        theme: buildAppTheme(sunflower),
      );
      final bar = tester.widget<Material>(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Material)).first,
      );
      expect(bar.color, sunflower.brand);
      final title = tester.widget<RichText>(
        find.descendant(of: find.byType(AppBar), matching: find.byType(RichText)).first,
      );
      expect(title.text.style?.color, sunflower.onBrand);
      final button = tester.widget<RichText>(
        find.descendant(of: find.byType(TextButton), matching: find.byType(RichText)).first,
      );
      expect(button.text.style?.color, sunflower.primary);
    });

    testWidgets('a yellow category gets its outline; a blue one does not', (tester) async {
      await pumpWithFakes(
        tester,
        const Column(
          children: [
            CategoryAvatar(
              key: Key('yellow'),
              category: Category(
                id: 'e',
                name: 'Electricity',
                kind: TxnType.expense,
                color: Color(0xFFFDD835),
                archived: false,
                iconKey: 'bolt',
              ),
            ),
            CategoryAvatar(
              key: Key('blue'),
              category: Category(
                id: 't',
                name: 'Transport',
                kind: TxnType.expense,
                color: Color(0xFF1E88E5),
                archived: false,
                iconKey: 'local_taxi',
              ),
            ),
          ],
        ),
        theme: buildAppTheme(themeTokensFor('marigold')),
      );
      expect(
        find.descendant(of: find.byKey(const Key('yellow')), matching: find.byKey(const ValueKey('circle-edge'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('blue')), matching: find.byKey(const ValueKey('circle-edge'))),
        findsNothing,
      );
      // Transport's glyph is now dark (white was only 3.7:1 on #1E88E5), as on the web.
      final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const Key('blue')), matching: find.byType(Icon)));
      expect(icon.color, kDarkGlyph);
    });
  });
}
