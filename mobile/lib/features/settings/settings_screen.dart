import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../lock/lock_controller.dart';
import '../reminders/reminder_plan.dart';
import '../reminders/reminder_sync.dart';
import 'export_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _toggleFingerprint(BuildContext context, WidgetRef ref, bool enable) async {
    if (enable) {
      // Only switch on after one successful scan.
      final ok = await ref
          .read(localAuthProvider)
          .authenticate(localizedReason: 'Confirm your fingerprint for Ventrafin', biometricOnly: true)
          .catchError((_) => false);
      if (!ok) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fingerprint wasn't confirmed.")));
        }
        return;
      }
    }
    await ref.read(lockControllerProvider.notifier).setBiometricEnabled(enable);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your data stays in your account. Sign in with Google to come back. Reminders stop on this phone until then.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await ref.read(lockControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(currentUserProvider)?.email ?? '';
    final available = ref.watch(biometricsAvailableProvider).value ?? false;
    final enabled = ref.watch(biometricEnabledProvider).value ?? false;
    final heading = Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('Signed in with Google'),
            subtitle: Text(email),
          ),
          const Divider(),
          ListTile(title: Text('Reminders', style: heading)),
          const RemindersSection(),
          const Divider(),
          ListTile(
            title: Text('Theme', style: heading),
            subtitle: const Text('Also changes the web app'),
          ),
          const ThemePicker(),
          const Divider(),
          ListTile(title: Text('Your data', style: heading)),
          ListTile(
            key: const Key('export-tile'),
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export transactions (CSV)'),
            subtitle: const Text('A file for Excel, to share by email, Drive or WhatsApp. To import, use the web app.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final count = await showExportSheet(context);
              if (count != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Exported $count ${count == 1 ? 'transaction' : 'transactions'}.')),
                );
              }
            },
          ),
          const Divider(),
          ListTile(title: Text('App lock', style: heading)),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Unlock with fingerprint'),
            subtitle: Text(available ? 'Pattern stays available as a backup' : 'No fingerprint set up on this phone'),
            value: enabled && available,
            onChanged: available ? (v) => _toggleFingerprint(context, ref, v) : null,
          ),
          ListTile(
            leading: const Icon(Icons.pattern),
            title: const Text('Change unlock pattern'),
            onTap: () => context.push('/more/settings/change-pattern'),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Auto-lock'),
            subtitle: Text(
              'When the app is reopened after ${kRelockAfterBackground.inSeconds} seconds in the background',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => _signOut(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Saves a settings change; says so if it fails (the switch flips back).
Future<void> _save(BuildContext context, WidgetRef ref, ProfilePatch patch) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!ref.read(isOnlineProvider)) {
    messenger.showSnackBar(const SnackBar(content: Text("There's no internet connection. Nothing was changed.")));
    return;
  }
  try {
    await ref.read(pendingProfileProvider.notifier).save(patch);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Not saved. ${describeError(e)}')));
  }
}

/// Daily reminder, bill reminders (master switch and how early), the bills
/// themselves, and what Android allows.
class RemindersSection extends ConsumerWidget {
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(effectiveProfileProvider);
    final permissions = ref.watch(reminderPermissionsProvider).value;
    final bills = ref.watch(billsProvider).value;
    if (profile == null) {
      return ref.watch(profileProvider).hasError
          ? ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text("Couldn't load your settings"),
              trailing: TextButton(onPressed: () => ref.invalidate(profileProvider), child: const Text('Retry')),
            )
          : const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    }
    final anyOn = profile.dailyReminderEnabled || profile.billRemindersEnabled;
    final days = profile.billReminderDaysBefore;
    final withReminder = bills?.where((b) => b.reminderEnabled).length ?? 0;

    return Column(
      children: [
        if (anyOn && permissions != null && !permissions.notificationsAllowed)
          _PermissionBanner(
            key: const Key('notifications-blocked'),
            icon: Icons.notifications_off,
            text: "Notifications are off for Ventrafin, so reminders can't appear.",
            action: 'Allow',
            onPressed: () async {
              final notifications = ref.read(reminderNotificationsProvider);
              final granted = await notifications.requestNotificationPermission();
              // Android stops showing its prompt after two refusals: open the
              // app's notification settings instead.
              if (!granted) await notifications.openNotificationSettings();
              ref.invalidate(reminderPermissionsProvider);
            },
          ),
        SwitchListTile(
          key: const Key('daily-reminder-switch'),
          secondary: const Icon(Icons.edit_note),
          title: const Text("Daily reminder to log expenses"),
          subtitle: Text(
            profile.dailyReminderEnabled ? 'Every day at ${formatTimeOfDay(profile.dailyReminderTime)}' : 'Off',
          ),
          value: profile.dailyReminderEnabled,
          onChanged: (v) => _save(context, ref, ProfilePatch(dailyReminderEnabled: v)),
        ),
        ListTile(
          key: const Key('daily-reminder-time'),
          enabled: profile.dailyReminderEnabled,
          leading: const Icon(Icons.schedule),
          title: const Text('Reminder time'),
          subtitle: const Text('India time'),
          trailing: Text(formatTimeOfDay(profile.dailyReminderTime), style: Theme.of(context).textTheme.titleSmall),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: profile.dailyReminderTime,
              helpText: 'Daily reminder time',
            );
            if (picked != null && context.mounted) await _save(context, ref, ProfilePatch(dailyReminderTime: picked));
          },
        ),
        SwitchListTile(
          key: const Key('bill-reminders-switch'),
          secondary: const Icon(Icons.receipt_long),
          title: const Text('Bill and EMI reminders'),
          subtitle: Text(
            profile.billRemindersEnabled
                ? 'For every bill with its own reminder on. Doesn\'t affect the daily reminder.'
                : 'Off for all bills. The daily reminder is separate.',
          ),
          value: profile.billRemindersEnabled,
          onChanged: (v) => _save(context, ref, ProfilePatch(billRemindersEnabled: v)),
        ),
        ListTile(
          key: const Key('bill-reminder-days'),
          enabled: profile.billRemindersEnabled,
          leading: const Icon(Icons.event_available),
          title: const Text('When to remind'),
          subtitle: Text(
            days == 0
                ? 'On the due date, at $kBillReminderTime'
                : '$days ${days == 1 ? 'day' : 'days'} before, and on the due date, at $kBillReminderTime',
          ),
          trailing: DropdownButton<int>(
            value: days,
            underline: const SizedBox.shrink(),
            onChanged: profile.billRemindersEnabled
                ? (v) => v == null ? null : _save(context, ref, ProfilePatch(billReminderDaysBefore: v))
                : null,
            items: [
              for (var d = 0; d <= kMaxBillReminderDaysBefore; d++)
                DropdownMenuItem(value: d, child: Text(d == 0 ? 'On the day' : '$d ${d == 1 ? 'day' : 'days'} before')),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.event_note),
          title: const Text('Your bills'),
          subtitle: Text(
            bills == null
                ? '…'
                : bills.isEmpty
                ? 'None yet. Add them on the Bills tab.'
                : '${bills.length} ${bills.length == 1 ? 'bill' : 'bills'}, $withReminder with reminders on',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/bills'),
        ),
        if (anyOn && permissions != null && permissions.notificationsAllowed && !permissions.exactAlarmsAllowed)
          _PermissionBanner(
            key: const Key('exact-alarms-off'),
            icon: Icons.alarm_off,
            text:
                'Android may deliver reminders a few minutes late to save battery. '
                'Allow "Alarms & reminders" for Ventrafin to get them on time.',
            action: 'Allow',
            onPressed: () async {
              await ref.read(reminderNotificationsProvider).requestExactAlarms();
              ref.invalidate(reminderPermissionsProvider);
            },
          ),
        if (anyOn && (permissions?.notificationsAllowed ?? false))
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Send a test reminder'),
            subtitle: const Text('Check that reminders reach this phone'),
            onTap: () async {
              await ref.read(reminderNotificationsProvider).showTest();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Sent. It should appear at the top of the screen.')));
              }
            },
          ),
      ],
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kUncategorizedColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: kUncategorizedInkColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: kUncategorizedInkColor)),
          ),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}

/// The six themes as a list with their colours. Picking one applies it
/// straight away and saves it to the profile, so the web app follows.
class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeIdProvider);
    final signedIn = ref.watch(effectiveProfileProvider) != null;
    return RadioGroup<String>(
      groupValue: current,
      onChanged: (id) {
        if (id != null && id != current && signedIn) _save(context, ref, ProfilePatch(theme: id));
      },
      child: Column(
        children: [
          for (final t in kThemes)
            RadioListTile<String>(
              key: Key('theme-${t.id}'),
              value: t.id,
              enabled: signedIn,
              title: Text(t.name),
              subtitle: Text(t.description),
              secondary: _Swatch(tokens: t),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.tokens});

  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 28,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: tokens.brand,
                alignment: Alignment.center,
                child: Text(
                  'Aa',
                  style: TextStyle(color: tokens.onBrand, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
            Expanded(flex: 2, child: Container(color: tokens.accent)),
          ],
        ),
      ),
    );
  }
}
