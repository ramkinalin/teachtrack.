import 'package:flutter_test/flutter_test.dart';
import 'package:teachtrack/features/timetable/data/local/timetable_seed.dart';
import 'package:teachtrack/features/timetable/domain/entities/period.dart';
import 'package:teachtrack/features/timetable/domain/period_shifter.dart';

void main() {
  final List<Period> schedule = TimetableSeed.defaultPeriods();

  group('shiftTo', () {
    test('moves every period by the same offset', () {
      // Default day starts at 08:00; move it to 09:15.
      final List<Period> shifted =
          PeriodShifter.shiftTo(schedule, 9 * 60 + 15)!;

      expect(shifted.first.startMinute, 9 * 60 + 15);
      for (int i = 0; i < schedule.length; i++) {
        expect(
          shifted[i].startMinute - schedule[i].startMinute,
          75,
          reason: 'uniform offset keeps gaps intact',
        );
      }
    });

    test('preserves each period duration exactly', () {
      final List<Period> shifted = PeriodShifter.shiftTo(schedule, 7 * 60)!;

      for (int i = 0; i < schedule.length; i++) {
        expect(shifted[i].duration, schedule[i].duration);
      }
    });

    test('preserves break flags, labels and order', () {
      final List<Period> shifted = PeriodShifter.shiftTo(schedule, 10 * 60)!;

      expect(
        shifted.map((Period p) => p.id),
        schedule.map((Period p) => p.id),
      );
      expect(
        shifted.where((Period p) => p.isBreak).map((Period p) => p.id),
        schedule.where((Period p) => p.isBreak).map((Period p) => p.id),
      );
    });

    test('shifting earlier works too', () {
      final List<Period> shifted =
          PeriodShifter.shiftTo(schedule, 7 * 60 + 30)!;

      expect(shifted.first.startMinute, 7 * 60 + 30);
      expect(shifted.last.endMinute, schedule.last.endMinute - 30);
    });

    test('an unchanged start time returns the same schedule', () {
      expect(PeriodShifter.shiftTo(schedule, 8 * 60), schedule);
    });

    test('refuses a shift that would push the day past midnight', () {
      // The default day ends at 15:00; starting at 23:00 would wrap.
      expect(
        PeriodShifter.shiftTo(schedule, 23 * 60),
        isNull,
        reason: 'refusal must be distinguishable from success',
      );
    });

    test('refuses a shift that would move a period before midnight', () {
      expect(PeriodShifter.shiftTo(schedule, -60), isNull);
    });

    test('an empty schedule cannot be shifted', () {
      expect(PeriodShifter.shiftTo(<Period>[], 9 * 60), isNull);
    });

    test('works when the input is not already sorted', () {
      final List<Period> reversed = schedule.reversed.toList();

      final List<Period> shifted = PeriodShifter.shiftTo(reversed, 9 * 60)!;

      expect(shifted.first.id, schedule.first.id, reason: 'sorted on the way out');
      expect(shifted.first.startMinute, 9 * 60);
    });
  });

  group('firstStartMinute', () {
    test('returns the earliest start', () {
      expect(PeriodShifter.firstStartMinute(schedule), 8 * 60);
    });

    test('is null for an empty schedule', () {
      expect(PeriodShifter.firstStartMinute(<Period>[]), isNull);
    });
  });
}
