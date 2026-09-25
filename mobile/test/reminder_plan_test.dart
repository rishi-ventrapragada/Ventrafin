import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/features/reminders/reminder_plan.dart';

/// 25 Sep 2026, 10:00 IST (04:30 UTC).
final _now = DateTime.utc(2026, 9, 25, 4, 30);

const _profile = Profile(
  theme: 'ocean',
  dailyReminderEnabled: true,
  dailyReminderTime: TimeOfDay(hour: 20, minute: 30),
  billRemindersEnabled: true,
  billReminderDaysBefore: 3,
);

Profile _with({bool? daily, bool? bills, int? days, TimeOfDay? time}) => Profile(
  theme: 'ocean',
  dailyReminderEnabled: daily ?? true,
  dailyReminderTime: time ?? const TimeOfDay(hour: 20, minute: 30),
  billRemindersEnabled: bills ?? true,
  billReminderDaysBefore: days ?? 3,
);

Bill bill(
  String id, {
  int dueDay = 10,
  YearMonth nextMonth = const YearMonth(2026, 10),
  bool reminder = true,
  String name = 'BESCOM',
  BillKind kind = BillKind.utility,
}) {
  final due = billDueDate(nextMonth, dueDay);
  return Bill(
    id: id,
    name: name,
    kind: kind,
    amountPaise: 145000,
    dueDay: dueDay,
    accountId: 'acc-bank',
    categoryId: null,
    reminderEnabled: reminder,
    paidThroughMonth: nextMonth.previous,
    nextDueDate: due,
    daysUntil: due.difference(DateTime(2026, 9, 25)).inDays,
    status: BillStatus.upcoming,
    overdueCount: 0,
  );
}

List<String> _times(List<PlannedReminder> plan, ReminderKind kind) => [
  for (final r in plan.where((r) => r.kind == kind)) r.at.toIso8601String(),
];

void main() {
  group('due dates (same vectors as private.bill_due_date in the pgTAP tests)', () {
    test('clamped to the end of short months', () {
      expect(billDueDate(const YearMonth(2026, 2), 31), DateTime(2026, 2, 28));
      expect(billDueDate(const YearMonth(2028, 2), 30), DateTime(2028, 2, 29));
      expect(billDueDate(const YearMonth(2026, 4), 31), DateTime(2026, 4, 30));
      expect(billDueDate(const YearMonth(2026, 4), 15), DateTime(2026, 4, 15));
    });

    test('labels', () {
      expect(dueDayLabel(1), '1st of every month');
      expect(dueDayLabel(2), '2nd of every month');
      expect(dueDayLabel(11), '11th of every month');
      expect(dueDayLabel(22), '22nd of every month');
      expect(dueDayLabel(31), 'last day of every month');
    });
  });

  group('daily reminder', () {
    test('once a day at the chosen time, India time, opening Add', () {
      final plan = planReminders(profile: _profile, bills: const [], now: _now);
      expect(plan, hasLength(1));
      final daily = plan.single;
      expect(daily.kind, ReminderKind.daily);
      expect(daily.repeatsDaily, isTrue);
      expect(daily.id, kDailyReminderId);
      expect(daily.at, DateTime(2026, 9, 25, 20, 30));
      expect(daily.route, '/add');
    });

    test('already past today: starts tomorrow', () {
      final plan = planReminders(
        profile: _with(time: const TimeOfDay(hour: 9, minute: 0)),
        bills: const [],
        now: _now,
      );
      expect(plan.single.at, DateTime(2026, 9, 26, 9, 0));
    });

    test('the phone set to another time zone changes nothing (IST is computed from UTC)', () {
      final local = _now.toLocal();
      expect(planReminders(profile: _profile, bills: const [], now: local).single.at, DateTime(2026, 9, 25, 20, 30));
    });

    test('its own switch; unaffected by the bill master switch', () {
      expect(planReminders(profile: _with(daily: false), bills: const [], now: _now), isEmpty);
      expect(planReminders(profile: _with(bills: false), bills: [bill('b1')], now: _now).map((r) => r.kind), [
        ReminderKind.daily,
      ]);
    });
  });

  group('bill reminders', () {
    test('N days before and on the due date at 9:00, for three months ahead', () {
      final plan = planReminders(profile: _with(daily: false), bills: [bill('b1')], now: _now);
      expect(_times(plan, ReminderKind.billAhead), [
        '2026-10-07T09:00:00.000',
        '2026-11-07T09:00:00.000',
        '2026-12-07T09:00:00.000',
      ]);
      expect(_times(plan, ReminderKind.billDue), [
        '2026-10-10T09:00:00.000',
        '2026-11-10T09:00:00.000',
        '2026-12-10T09:00:00.000',
      ]);
      expect(plan.every((r) => r.route == '/bills'), isTrue);
      expect(plan.map((r) => r.id).toSet(), hasLength(plan.length), reason: 'ids are unique');
    });

    test('wording names the bill and the date, never the amount', () {
      final plan = planReminders(
        profile: _with(daily: false),
        bills: [bill('b1', kind: BillKind.emi, name: 'Home loan')],
        now: _now,
      );
      expect(plan.first.title, 'Home loan is due in 3 days');
      expect(plan.first.body, 'Your Home loan EMI is due on Sat, 10 Oct.');
      expect(plan[1].title, 'Home loan is due today');
      expect(plan.any((r) => r.body.contains('₹') || r.title.contains('1,450')), isFalse);
    });

    test('0 days before: only on the due date', () {
      final plan = planReminders(profile: _with(daily: false, days: 0), bills: [bill('b1')], now: _now);
      expect(plan.map((r) => r.kind).toSet(), {ReminderKind.billDue});
      expect(plan, hasLength(3));
    });

    test("a bill's own switch, and the master switch, turn its reminders off", () {
      expect(planReminders(profile: _with(daily: false), bills: [bill('b1', reminder: false)], now: _now), isEmpty);
      expect(planReminders(profile: _with(daily: false, bills: false), bills: [bill('b1')], now: _now), isEmpty);
    });

    test('nothing in the past: due in 2 days skips the "3 days before" one; overdue month skipped', () {
      // Due 27 Sep (2 days away): the 24 Sep "ahead" reminder has passed.
      final soon = planReminders(
        profile: _with(daily: false),
        bills: [bill('b1', dueDay: 27, nextMonth: const YearMonth(2026, 9))],
        now: _now,
      );
      expect(_times(soon, ReminderKind.billDue).first, '2026-09-27T09:00:00.000');
      expect(_times(soon, ReminderKind.billAhead).first, '2026-10-24T09:00:00.000');
      // Unpaid since 5 Sep: that month is overdue (shown on the Bills screen);
      // October and November still get their reminders.
      final overdue = planReminders(
        profile: _with(daily: false),
        bills: [bill('b1', dueDay: 5, nextMonth: const YearMonth(2026, 9))],
        now: _now,
      );
      expect(_times(overdue, ReminderKind.billDue), ['2026-10-05T09:00:00.000', '2026-11-05T09:00:00.000']);
    });

    test('due day 31 follows short months', () {
      final plan = planReminders(
        profile: _with(daily: false, days: 0),
        bills: [bill('b1', dueDay: 31, nextMonth: const YearMonth(2027, 1))],
        now: _now,
      );
      expect(_times(plan, ReminderKind.billDue), [
        '2027-01-31T09:00:00.000',
        '2027-02-28T09:00:00.000',
        '2027-03-31T09:00:00.000',
      ]);
    });

    test('several bills get distinct ids', () {
      final plan = planReminders(
        profile: _profile,
        bills: [for (var i = 0; i < 12; i++) bill('b$i', dueDay: i + 1)],
        now: _now,
      );
      expect(plan.map((r) => r.id).toSet(), hasLength(plan.length));
    });
  });

  group('profile and time parsing', () {
    test('Postgres time <-> TimeOfDay', () {
      expect(parseDbTime('20:30:00'), const TimeOfDay(hour: 20, minute: 30));
      expect(parseDbTime('07:05'), const TimeOfDay(hour: 7, minute: 5));
      expect(parseDbTime('bad'), isNull);
      expect(toDbTime(const TimeOfDay(hour: 7, minute: 5)), '07:05');
      expect(formatTimeOfDay(const TimeOfDay(hour: 20, minute: 30)), '8:30 pm');
      expect(formatTimeOfDay(const TimeOfDay(hour: 0, minute: 0)), '12:00 am');
    });

    test('Profile.fromRow and ProfilePatch only send what changed', () {
      final p = Profile.fromRow({
        'theme': 'forest',
        'daily_reminder_enabled': false,
        'daily_reminder_time': '21:15:00',
        'bill_reminders_enabled': true,
        'bill_reminder_days_before': 5,
      });
      expect(p.theme, 'forest');
      expect(p.dailyReminderTime, const TimeOfDay(hour: 21, minute: 15));
      expect(p.billReminderDaysBefore, 5);
      expect(const ProfilePatch(theme: 'garden').toRow(), {'theme': 'garden'});
      expect(const ProfilePatch(dailyReminderTime: TimeOfDay(hour: 6, minute: 0)).toRow(), {
        'daily_reminder_time': '06:00',
      });
    });

    test('Bill.fromScheduleRow', () {
      final b = Bill.fromScheduleRow({
        'id': 'b1',
        'name': 'BESCOM',
        'kind': 'utility',
        'amount_paise': 145000,
        'due_day': 31,
        'account_id': 'acc',
        'category_id': null,
        'reminder_enabled': true,
        'paid_through_month': '2026-01-01',
        'next_due_date': '2026-02-28',
        'days_until': -33,
        'status': 'overdue',
        'overdue_count': 2,
      });
      expect(b.status, BillStatus.overdue);
      expect(b.nextDueMonth, const YearMonth(2026, 2));
      expect(b.paidThroughMonth, const YearMonth(2026, 1));
      expect(b.toDraft().toRow(), containsPair('due_day', 31));
      expect(b.toDraft().toRow().containsKey('paid_through_month'), isFalse);
    });
  });
}
