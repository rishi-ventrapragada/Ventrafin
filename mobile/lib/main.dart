import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'data/providers.dart';
import 'data/secure_session_storage.dart';
import 'features/lock/lock_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  if (!config.isValid) {
    runApp(ConfigErrorApp(problems: config.problems));
    return;
  }

  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      // Session tokens in Keystore-backed storage, not plain SharedPreferences.
      localStorage: SecureSessionStorage(secureStorage),
      // Native ID-token sign-in: no deep links / browser redirects to handle.
      detectSessionInUri: false,
    ),
  );

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      // Show errors immediately with a Retry button instead of silently
      // retrying in the background (Riverpod 3's default).
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const VentrafinApp(),
    ),
  );
}
