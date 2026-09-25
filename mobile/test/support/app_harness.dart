import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventrafin/app.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/features/lock/lock_controller.dart';
import 'package:ventrafin/features/reminders/reminder_prompt.dart';
import 'package:ventrafin/router.dart';

import 'fake_repository.dart';

/// Pumps the whole app (router, tabs, lock gate) signed in as a user with a
/// pattern, on the fake repository. Unlocked unless [unlocked] is false.
Future<(FakeRepository, ProviderContainer)> pumpApp(
  WidgetTester tester, {
  FakeRepository? repo,
  bool unlocked = true,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // The reminder explanation has been shown before: no dialog on start.
  SharedPreferences.setMockInitialValues({kReminderPromptShownKey: true});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final r = repo ?? FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        repositoryProvider.overrideWithValue(r),
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue('user-1'),
        currentUserProvider.overrideWithValue(null),
        clockProvider.overrideWithValue(() => fixedClock),
        isOnlineProvider.overrideWithValue(true),
        hasPatternProvider.overrideWith((ref) async => true),
        biometricEnabledProvider.overrideWith((ref) async => false),
        biometricsAvailableProvider.overrideWith((ref) async => false),
        ...overrides,
      ],
      child: const VentrafinApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(VentrafinApp)));
  if (unlocked) {
    container.read(lockControllerProvider.notifier).unlock();
    await tester.pumpAndSettle();
  }
  return (r, container);
}

/// Where the top screen is, e.g. `/transactions/t1` (a pushed screen
/// included).
String location(ProviderContainer container) => container.read(routerProvider).state.matchedLocation;

/// Android's back button. True if the app handled it; false means Android
/// would close the app.
Future<bool> pressBack(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

/// Taps a bottom-navigation tab by its label.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// The selected bottom-navigation tab.
int selectedTab(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
