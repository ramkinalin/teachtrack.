import 'package:flutter_test/flutter_test.dart';
import 'package:teachtrack/features/timetable/domain/entities/class_session.dart';
import 'package:teachtrack/features/timetable/domain/entities/period.dart';
import 'package:teachtrack/features/timetable/domain/entities/scheduled_class.dart';
import 'package:teachtrack/features/timetable/domain/entities/timetable_entry.dart';
import 'package:teachtrack/features/timetable/domain/schedule_resolver.dart';

/// 2026-07-30 is a Thursday.
final DateTime _day = DateTime(2026, 7, 30);

Period _period(
  String id,
  int startHour,
  int startMinute,
  int endHour,
  int endMinute, {
  int order = 1,
  bool isBreak = false,
}) =>
    Period(
      id: id,
      label: id,
      startMinute: startHour * 60 + startMinute,
      endMinute: endHour * 60 + endMinute,
      sortOrder: order,
      isBreak: isBreak,
    );

ScheduledClass _scheduled(
  Period period, {
  String subject = 'Mathematics',
  ClassSessionStatus? status,
}) {
  final TimetableEntry entry = TimetableEntry(
    id: 'entry-${period.id}',
    weekday: _day.weekday,
    periodId: period.id,
    subject: subject,
    classGroup: '8B',
  );

  return ScheduledClass(
    entry: entry,
    period: period,
    date: _day,
    session: status == null
        ? null
        : ClassSession(
            id: ClassSession.buildId(_day, entry.id),
            entryId: entry.id,
            date: _day,
            status: status,
          ),
  );
}

DateTime _at(int hour, int minute, [int second = 0]) =>
    DateTime(_day.year, _day.month, _day.day, hour, minute, second);

void main() {
  final Period p1 = _period('p1', 8, 0, 8, 45, order: 1);
  final Period breakTime =
      _period('break', 8, 45, 9, 0, order: 2, isBreak: true);
  final Period p2 = _period('p2', 9, 0, 9, 45, order: 3);

  late List<ScheduledClass> schedule;

  setUp(() {
    schedule = <ScheduledClass>[
      _scheduled(p1),
      _scheduled(breakTime, subject: 'Break'),
      _scheduled(p2, subject: 'Science'),
    ];
  });

  group('resolve', () {
    test('identifies the class in progress and the one after it', () {
      final ScheduleSnapshot snapshot =
          ScheduleResolver.resolve(schedule, _at(8, 20));

      expect(snapshot.current?.period.id, 'p1');
      expect(snapshot.next?.period.id, 'break');
      expect(snapshot.remainingInCurrent, const Duration(minutes: 25));
    });

    test('the first minute of a period counts as inside it', () {
      final ScheduleSnapshot snapshot =
          ScheduleResolver.resolve(schedule, _at(8, 0));

      expect(snapshot.current?.period.id, 'p1');
      expect(snapshot.remainingInCurrent, const Duration(minutes: 45));
    });

    test('the end minute belongs to the next period, not the ending one', () {
      // 08:45 is p1.endMinute and break.startMinute — a teacher at 08:45 is on
      // break, not still teaching.
      final ScheduleSnapshot snapshot =
          ScheduleResolver.resolve(schedule, _at(8, 45));

      expect(snapshot.current?.period.id, 'break');
      expect(snapshot.next?.period.id, 'p2');
    });

    test('seconds are subtracted so the countdown does not sit a minute high',
        () {
      final ScheduleSnapshot snapshot =
          ScheduleResolver.resolve(schedule, _at(8, 44, 30));

      expect(snapshot.remainingInCurrent, const Duration(seconds: 30));
    });

    test('before the day starts there is no current class, only a next one', () {
      final ScheduleSnapshot snapshot =
          ScheduleResolver.resolve(schedule, _at(7, 30));

      expect(snapshot.current, isNull);
      expect(snapshot.next?.period.id, 'p1');
      expect(snapshot.untilNext, const Duration(minutes: 30));
      expect(snapshot.isFreePeriod, isTrue);
      expect(snapshot.dayIsOver, isFalse);
    });

    test('after the last period the day is over', () {
      final ScheduleSnapshot snapshot =
          ScheduleResolver.resolve(schedule, _at(16, 0));

      expect(snapshot.current, isNull);
      expect(snapshot.next, isNull);
      expect(snapshot.dayIsOver, isTrue);
    });

    test('a gap between periods reports free with the next class pending', () {
      final ScheduleSnapshot snapshot = ScheduleResolver.resolve(
        <ScheduledClass>[_scheduled(p1), _scheduled(p2)],
        _at(8, 50),
      );

      expect(snapshot.current, isNull);
      expect(snapshot.next?.period.id, 'p2');
      expect(snapshot.untilNext, const Duration(minutes: 10));
    });

    test('an unordered schedule still resolves correctly', () {
      final ScheduleSnapshot snapshot = ScheduleResolver.resolve(
        <ScheduledClass>[_scheduled(p2), _scheduled(breakTime), _scheduled(p1)],
        _at(8, 30),
      );

      expect(snapshot.current?.period.id, 'p1');
      expect(snapshot.next?.period.id, 'break');
    });

    test('an empty schedule is treated as the day being over', () {
      final ScheduleSnapshot snapshot =
          ScheduleResolver.resolve(<ScheduledClass>[], _at(9, 0));

      expect(snapshot.dayIsOver, isTrue);
      expect(snapshot.remainingLabel, isNull);
    });
  });

  group('unmarkedPast', () {
    test('lists finished lessons with nothing recorded, ignoring breaks', () {
      final List<ScheduledClass> unmarked =
          ScheduleResolver.unmarkedPast(schedule, 10 * 60);

      expect(
        unmarked.map((ScheduledClass c) => c.period.id),
        <String>['p1', 'p2'],
        reason: 'the break is not actionable',
      );
    });

    test('excludes lessons already marked', () {
      final List<ScheduledClass> unmarked = ScheduleResolver.unmarkedPast(
        <ScheduledClass>[
          _scheduled(p1, status: ClassSessionStatus.completed),
          _scheduled(p2, status: ClassSessionStatus.cancelled),
        ],
        10 * 60,
      );

      expect(unmarked, isEmpty);
    });

    test('excludes lessons that have not finished yet', () {
      final List<ScheduledClass> unmarked =
          ScheduleResolver.unmarkedPast(schedule, 8 * 60 + 20);

      expect(unmarked, isEmpty);
    });
  });
}
