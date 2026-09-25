# /shared — assets used by both apps

Placeholder. `theme-tokens.json` lands here in **Phase 7 (Polish)**, see `ARCHITECTURE.md` § 8.
It is the single source for the six light-mode colour themes (Ocean, Sunset, Forest, Garden, Sunflower, Marigold).
Theme ids must match the `profiles.theme` check constraint.

## `category-style.json`

The curated category icon keys (with labels and picker groups), the 24-colour palette, the Uncategorized/Transfer looks and the merchant letter-badge rule (DECISIONS.md D13, D14).
- The icon keys must equal the database's `categories_icon_check` constraint, and the palette must equal `private.category_palette()`.
- `mobile/test/category_style_test.dart` checks both against the latest migration, and checks the Flutter copy against this file.
- The web app imports this file directly (`web/src/lib/categoryStyle.ts`). `web/scripts/gen-icons.mjs` turns its icon keys into SVG paths (DECISIONS.md D17).
- `web/tests/unit/visuals.test.ts` checks the web copy of the rules: every key has a glyph, the palette matches, and the merchant badges equal vectors printed by the Dart code.
