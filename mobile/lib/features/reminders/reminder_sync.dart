import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'reminder_notifications.dart';
import 'reminder_plan.dart';

/// The notification service. main() overrides it with the real plugin.
final reminderNotificationsProvider = Provider<ReminderNotifications>((ref) => const NoReminderNotifications());

/// Routes of tapped reminders.
final reminderOpenedProvider = StreamProvider<String>((ref) => ref.watch(reminderNotificationsProvider).opened);

/// What Android allows right now. Re-read when the app comes back to the
/// foreground (the user may have changed it in Android Settings).
final reminderPermissionsProvider = FutureProvider<ReminderPermissions>(
  (ref) => ref.watch(reminderNotificationsProvider).permissions(),
);

/// The reminders that should be scheduled now.
final reminderPlanProvider = Provider<List<PlannedReminder>?>((ref) {
  final profile = ref.watch(effectiveProfileProvider);
  final bills = ref.watch(billsProvider).value;
  if (profile == null || bills == null) return null;
  return planReminders(profile: profile, bills: bills, now: ref.watch(clockProvider)());
});

/// Keeps the phone's scheduled notifications equal to [reminderPlanProvider]
/// while the signed-in app is showing: on start, when a setting or a bill
/// changes (here or on the web, via Realtime), and on returning to the app.
/// Writes are serialised so two quick changes can't interleave.
final reminderSyncProvider = Provider<void>((ref) {
  final plan = ref.watch(reminderPlanProvider);
  final permissions = ref.watch(reminderPermissionsProvider).value;
  if (plan == null || permissions == null) return;
  final notifications = ref.read(reminderNotificationsProvider);
  _queue = _queue
      .then((_) => notifications.replaceAll(plan, exact: permissions.exactAlarmsAllowed))
      .catchError((Object _) {}); // A failed reschedule is retried on the next change or resume.
});

Future<void> _queue = Future.value();
