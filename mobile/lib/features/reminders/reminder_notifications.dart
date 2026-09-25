import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_plan.dart';

/// What Android currently allows.
@immutable
class ReminderPermissions {
  const ReminderPermissions({required this.notificationsAllowed, required this.exactAlarmsAllowed});

  /// POST_NOTIFICATIONS (Android 13+) granted and notifications not blocked
  /// for the app. Without it nothing appears at all.
  final bool notificationsAllowed;

  /// SCHEDULE_EXACT_ALARM (Android 12+). Without it reminders still come, but
  /// Android may deliver them some minutes late to save battery.
  final bool exactAlarmsAllowed;
}

/// Local notifications for reminders (phone only, no server push). Behind an
/// interface so widget tests can use a fake.
abstract interface class ReminderNotifications {
  Future<ReminderPermissions> permissions();

  /// Shows Android's "Allow notifications?" prompt (Android 13+). Returns
  /// whether notifications are allowed afterwards. After two refusals
  /// Android stops asking; use [openNotificationSettings] then.
  Future<bool> requestNotificationPermission();

  /// Opens the system "Alarms & reminders" page for the app. Returns whether
  /// exact alarms are allowed afterwards.
  Future<bool> requestExactAlarms();

  /// The app's notification settings page in Android Settings.
  Future<void> openNotificationSettings();

  /// Cancels every scheduled reminder and schedules [plan] instead. With
  /// [exact] false (or when Android refuses exact alarms) they are scheduled
  /// as inexact alarms.
  Future<void> replaceAll(List<PlannedReminder> plan, {required bool exact});

  /// Shows a sample reminder now, to check that notifications arrive.
  Future<void> showTest();

  Future<void> cancelAll();

  /// Locations to open when a reminder is tapped (including the one that
  /// started the app).
  Stream<String> get opened;
}

const _dailyChannel = AndroidNotificationDetails(
  'daily_reminder',
  'Daily reminder',
  channelDescription: "Evening reminder to log the day's expenses",
  importance: Importance.defaultImportance,
  priority: Priority.defaultPriority,
  icon: 'ic_stat_ventrafin',
  category: AndroidNotificationCategory.reminder,
  // On a locked phone that hides sensitive content, only "Ventrafin" shows.
  visibility: NotificationVisibility.private,
);

const _billChannel = AndroidNotificationDetails(
  'bill_reminders',
  'Bill reminders',
  channelDescription: 'Before and on the due date of your bills and EMIs',
  importance: Importance.high,
  priority: Priority.high,
  icon: 'ic_stat_ventrafin',
  category: AndroidNotificationCategory.reminder,
  visibility: NotificationVisibility.private,
);

/// flutter_local_notifications on Android. Times are scheduled in
/// Asia/Kolkata, the app's only time zone, whatever the phone is set to.
class LocalReminderNotifications implements ReminderNotifications {
  LocalReminderNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _opened = StreamController<String>();
  late final tz.Location _india;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Call once from main(), before runApp.
  Future<void> init() async {
    tz_data.initializeTimeZones();
    _india = tz.getLocation('Asia/Kolkata');
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_ventrafin')),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) _open(launch!.notificationResponse?.payload);
  }

  void _open(String? route) {
    if (route != null && route.startsWith('/')) _opened.add(route);
  }

  @override
  Stream<String> get opened => _opened.stream;

  @override
  Future<ReminderPermissions> permissions() async {
    final android = _android;
    if (android == null) return const ReminderPermissions(notificationsAllowed: false, exactAlarmsAllowed: false);
    return ReminderPermissions(
      notificationsAllowed: await android.areNotificationsEnabled() ?? false,
      exactAlarmsAllowed: await android.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<bool> requestNotificationPermission() async => await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<bool> requestExactAlarms() async => await _android?.requestExactAlarmsPermission() ?? false;

  @override
  Future<void> openNotificationSettings() async => _android?.openAppNotificationSettings();

  @override
  Future<void> replaceAll(List<PlannedReminder> plan, {required bool exact}) async {
    await _plugin.cancelAll();
    var useExact = exact;
    for (final r in plan) {
      final at = tz.TZDateTime(_india, r.at.year, r.at.month, r.at.day, r.at.hour, r.at.minute);
      Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: at,
        title: r.title,
        body: r.body,
        payload: r.route,
        notificationDetails: NotificationDetails(android: r.repeatsDaily ? _dailyChannel : _billChannel),
        androidScheduleMode: mode,
        matchDateTimeComponents: r.repeatsDaily ? DateTimeComponents.time : null,
      );
      try {
        await schedule(useExact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle);
      } on PlatformException catch (e) {
        // Exact alarms were switched off in Android Settings since we last
        // checked: fall back to inexact ones rather than losing the reminder.
        if (!useExact || e.code != 'exact_alarms_not_permitted') rethrow;
        useExact = false;
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }
  }

  @override
  Future<void> showTest() => _plugin.show(
    id: 2,
    title: 'Ventrafin reminders are working',
    body: 'Your daily and bill reminders will look like this.',
    payload: '/more/settings',
    notificationDetails: const NotificationDetails(android: _dailyChannel),
  );

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// Does nothing: the default until main() provides the real one, and in
/// tests that don't care about reminders.
class NoReminderNotifications implements ReminderNotifications {
  const NoReminderNotifications();

  @override
  Future<ReminderPermissions> permissions() async =>
      const ReminderPermissions(notificationsAllowed: true, exactAlarmsAllowed: true);

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<bool> requestExactAlarms() async => true;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> replaceAll(List<PlannedReminder> plan, {required bool exact}) async {}

  @override
  Future<void> showTest() async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<String> get opened => const Stream.empty();
}
