import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Device-local UI preferences for the entry form: the last-used account and
/// payment method. These are conveniences, not financial data, so plain
/// SharedPreferences is fine (and this is not a local database/cache).
class EntryPrefs {
  EntryPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _accountKey = 'entry.lastAccountId';
  static const _methodKey = 'entry.lastPaymentMethod';

  String? get lastAccountId => _prefs.getString(_accountKey);

  PaymentMethod? get lastPaymentMethod => PaymentMethod.fromDb(_prefs.getString(_methodKey));

  Future<void> remember({required String accountId, PaymentMethod? method}) async {
    await _prefs.setString(_accountKey, accountId);
    if (method != null) await _prefs.setString(_methodKey, method.db);
  }
}
