import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import 'reminder_plan.dart';
import 'reminder_sync.dart';

/// SharedPreferences key: the first-run "Allow reminders?" explanation has
/// been shown on this phone (a UI preference, not data).
const String kReminderPromptShownKey = 'reminders.promptShown';

/// Once per install, when a reminder is switched on but Android doesn't
/// allow notifications yet: explain what they are for, then show Android's
/// own prompt. Declining is fine; Settings shows how to turn them on later.
/// Exact timing is not asked for here (Android sends people to a separate
/// Settings page for it); the Settings screen offers it.
Future<void> maybeAskForReminderPermission(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs.getBool(kReminderPromptShownKey) ?? false) return;

  final Profile? profile;
  try {
    profile = await ref.read(profileProvider.future);
  } catch (_) {
    return; // Try again next start.
  }
  if (profile == null || !(profile.dailyReminderEnabled || profile.billRemindersEnabled)) return;

  final notifications = ref.read(reminderNotificationsProvider);
  if ((await notifications.permissions()).notificationsAllowed) {
    await prefs.setBool(kReminderPromptShownKey, true);
    return;
  }
  await prefs.setBool(kReminderPromptShownKey, true);
  if (!context.mounted) return;
  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: const Text('Allow reminders?'),
      content: Text(
        'Ventrafin can remind you at ${formatTimeOfDay(profile!.dailyReminderTime)} to log the day\'s expenses, '
        'and at $kBillReminderTime before your bills and EMIs are due.\n\n'
        'You can change or switch these off any time in More › Settings.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
      ],
    ),
  );
  if (allow == true) await notifications.requestNotificationPermission();
  ref.invalidate(reminderPermissionsProvider);
}
