# /shared — assets used by both apps

## `theme-tokens.json`

The six light-mode colour themes (Ocean, Sunset, Forest, Garden, Sunflower, Marigold) and the semantic colours (expense red, income green, transfer grey, Uncategorized amber), for both apps (`ARCHITECTURE.md` § 8, `DECISIONS.md` D22).
- Theme ids must match the `profiles_theme_check` constraint; both apps' tests check it.
- The web app imports this file directly (`web/src/lib/theme.ts`). The phone's `mobile/lib/core/theme_tokens.g.dart` is generated from it with `dart run tool/gen_theme_tokens.dart`, and `mobile/test/theme_test.dart` fails if the generated file is stale.
- Both apps' theme tests check every theme for contrast (text on the brand colour, primary on every surface, amounts on every surface) and every palette colour on every theme's surfaces. After changing a value here, run both test suites.

## `category-style.json`

The curated category icon keys (with labels and picker groups), the 24-colour palette, the Uncategorized/Transfer looks, the glyph colour (white or dark) on every palette colour, and the merchant letter-badge rule (DECISIONS.md D13, D14, D20).
- The icon keys must equal the database's `categories_icon_check` constraint, and the palette must equal `private.category_palette()`.
- `mobile/test/category_style_test.dart` checks both against the latest migration, and checks the Flutter copy against this file.
- The web app imports this file directly (`web/src/lib/categoryStyle.ts`). `web/scripts/gen-icons.mjs` turns its icon keys into SVG paths (DECISIONS.md D17).
- `web/tests/unit/visuals.test.ts` checks the web copy of the rules: every key has a glyph, the palette matches, and the merchant badges equal vectors printed by the Dart code.
