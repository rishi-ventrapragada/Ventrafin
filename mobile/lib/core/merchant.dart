import 'dart:convert';

import 'category_style.dart';

/// Merchant letter badges: a small letter derived from the description,
/// coloured consistently per merchant. No logos and no logo service
/// (trademarks, and it would send merchant names to a third party); this is
/// computed on the phone from text it already has.
///
/// The rule is written down in /shared/category-style.json ("merchantBadge")
/// so the web app can produce identical badges.

/// Words that describe the payment rather than the merchant. Same list the
/// database uses when it learns a rule from a correction.
const Set<String> kMerchantFillerWords = {
  'upi', 'imps', 'neft', 'rtgs', 'ach', 'nach', 'pos', 'ecom', 'txn', 'ref', 'refno',
  'payment', 'paid', 'pay', 'sent', 'received', 'transfer', 'trf', 'dr', 'cr',
  'to', 'from', 'by', 'via', 'for', 'at', 'on', 'in', 'of', 'the', 'and', 'a', 'an',
  'rs', 'inr', 'bill', 'order',
};

/// Anything that isn't a letter, combining mark or digit separates words.
/// (Marks matter: Devanagari vowel signs are marks, and 'दूध' is one word.)
final RegExp _separators = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);
final RegExp _digitsOnly = RegExp(r'^\d+$');

/// The merchant word of a description, or null if there isn't one.
///   'UPI/SWIGGY/4471023@icici'     -> 'swiggy'
///   'Paid to Ramesh Kirana Store'  -> 'ramesh'
///   '4471023', ''                  -> null
String? merchantKey(String description) {
  final words = description.toLowerCase().split(_separators).where((w) => w.isNotEmpty);
  for (final w in words) {
    if (_digitsOnly.hasMatch(w) || kMerchantFillerWords.contains(w)) continue;
    return w;
  }
  return null;
}

/// FNV-1a (32-bit) over the UTF-8 bytes: stable across runs, devices and
/// languages, unlike `String.hashCode`.
int fnv1a32(String s) {
  var hash = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Letter and palette colour for a merchant badge, or null when the
/// description names no merchant.
({String letter, String colorHex})? merchantBadgeFor(String description) {
  final key = merchantKey(description);
  if (key == null) return null;
  final letter = String.fromCharCode(key.runes.first).toUpperCase();
  final colorHex = kCategoryPaletteHex[fnv1a32(key) % kCategoryPaletteHex.length];
  return (letter: letter, colorHex: colorHex);
}
