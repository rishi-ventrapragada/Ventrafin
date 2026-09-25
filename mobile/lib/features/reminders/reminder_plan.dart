import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/india_time.dart';
import '../../data/models.dart';

/// Which reminders the phone should have scheduled, worked out from the
/// profile and the bills alone (no plugin, no clock of its own), so it can be
/// tested directly. The scheduler replaces every pending notification with
/// this plan whenever the inputs change (DECISIONS.md D24).
///
/// Rules:
///  * Daily reminder: every day at the profile's time, India time. It has its
///    own switch; the bill master switch doesn't affect it.
///  * Bill reminders, only when the master switch AND the bill's own switch
///    are on: at [kBillReminderTime] on the due date, and
///    `billReminderDaysBefore` days earlier (none when that is 0). For the
///    next unpaid month and the ones after it, [kBillMonthsAhead] months in
///    all, so reminders keep coming even if the app isn't opened for weeks.
///    A month that is already overdue gets nothing more: the Bills screen
///    shows it in red.
///  * Nothing in the past is scheduled.

/// Bill reminders go off at 9:00 am India time: early enough to pay that day.
const kBillReminderHour = 9;
const kBillReminderMinute = 0;
const String kBillReminderTime = '9:00 am';

/// How many months of each bill are scheduled ahead.
const int kBillMonthsAhead = 3;

enum ReminderKind { daily, billAhead, billDue }

/// Where tapping a notification opens the app.
const String kDailyReminderRoute = '/add';
const String kBillReminderRoute = '/bills';

@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
    required this.route,
  });

  /// Stable within one plan; the scheduler cancels everything first.
  final int id;
  final ReminderKind kind;

  /// Wall-clock date and time in India (the fields are IST, not device time).
  /// For [ReminderKind.daily] only the time matters: it repeats every day.
  final DateTime at;
  final String title;
  final String body;

  /// go_router location to open when tapped.
  final String route;

  bool get repeatsDaily => kind == ReminderKind.daily;

  @override
  String toString() => '$kind ${at.toIso8601String()} "$title: $body"';
}

/// Notification id of the daily reminder; bill reminders use 1000 upwards.
const int kDailyReminderId = 1;

/// The plan for [profile] and [bills] at [now] (any time zone; converted to
/// India time here).
List<PlannedReminder> planReminders({required Profile profile, required List<Bill> bills, required DateTime now}) {
  final ist = now.toUtc().add(kIndiaOffset);
  final nowIst = DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
  final plan = <PlannedReminder>[];

  if (profile.dailyReminderEnabled) {
    final t = profile.dailyReminderTime;
    var next = DateTime(nowIst.year, nowIst.month, nowIst.day, t.hour, t.minute);
    if (!next.isAfter(nowIst)) next = DateTime(next.year, next.month, next.day + 1, t.hour, t.minute);
    plan.add(
      PlannedReminder(
        id: kDailyReminderId,
        kind: ReminderKind.daily,
        at: next,
        title: "Log today's expenses",
        body: 'Tap to add what you spent today.',
        route: kDailyReminderRoute,
      ),
    );
  }

  if (!profile.billRemindersEnabled) return plan;

  final today = DateTime(nowIst.year, nowIst.month, nowIst.day);
  final sorted = [...bills]..sort((a, b) => a.id.compareTo(b.id));
  for (var i = 0; i < sorted.length; i++) {
    final bill = sorted[i];
    if (!bill.reminderEnabled) continue;
    for (var k = 0; k < kBillMonthsAhead; k++) {
      var month = bill.nextDueMonth;
      for (var j = 0; j < k; j++) {
        month = month.next;
      }
      final due = billDueDate(month, bill.dueDay);
      if (due.isBefore(today)) continue; // overdue: shown on the Bills screen instead
      final baseId = 1000 + i * 10 + k * 2;
      final dueLabel = DateFormat('EEE, d MMM').format(due);
      final what = bill.kind == BillKind.emi ? 'EMI' : 'bill';

      final days = profile.billReminderDaysBefore;
      if (days > 0) {
        final ahead = DateTime(due.year, due.month, due.day - days, kBillReminderHour, kBillReminderMinute);
        if (ahead.isAfter(nowIst)) {
          plan.add(
            PlannedReminder(
              id: baseId,
              kind: ReminderKind.billAhead,
              at: ahead,
              title: '${bill.name} is due in $days ${days == 1 ? 'day' : 'days'}',
              body: 'Your ${bill.name} $what is due on $dueLabel.',
              route: kBillReminderRoute,
            ),
          );
        }
      }
      final onDay = DateTime(due.year, due.month, due.day, kBillReminderHour, kBillReminderMinute);
      if (onDay.isAfter(nowIst)) {
        plan.add(
          PlannedReminder(
            id: baseId + 1,
            kind: ReminderKind.billDue,
            at: onDay,
            title: '${bill.name} is due today',
            body: 'Your ${bill.name} $what is due today. Mark it paid in Ventrafin once it is done.',
            route: kBillReminderRoute,
          ),
        );
      }
    }
  }
  return plan;
}
