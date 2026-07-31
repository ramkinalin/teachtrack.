import 'package:flutter_test/flutter_test.dart';
import 'package:teachtrack/features/events/domain/entities/school_event.dart';
import 'package:teachtrack/features/events/domain/event_reminder_planner.dart';

void main() {
  final DateTime thursday = DateTime(2026, 7, 30);

  SchoolEvent event({
    String id = 'ev1',
    DateTime? date,
    SchoolEventCategory category = SchoolEventCategory.classTest,
    String title = 'Unit test 2',
    int? startMinute,
    List<int> reminders = const <int>[],
    String classGroup = '',
    String subject = '',
    String opponent = '',
    String location = '',
  }) =>
      SchoolEvent(
        id: id,
        date: date ?? thursday,
        category: category,
        title: title,
        startMinute: startMinute,
        reminderLeadMinutes: reminders,
        classGroup: classGroup,
        subject: subject,
        opponent: opponent,
        location: location,
      );

  group('plan', () {
    test('schedules one reminder per lead, soonest first', () {
      final List<ScheduledReminder> plan = EventReminderPlanner.plan(
        <SchoolEvent>[
          event(startMinute: 10 * 60, reminders: <int>[1440, 60]),
        ],
        DateTime(2026, 7, 28),
      );

      expect(plan, hasLength(2));
      expect(plan.first.when, DateTime(2026, 7, 29, 10));
      expect(plan.last.when, DateTime(2026, 7, 30, 9));
    });

    test('drops reminders already in the past', () {
      // Standing at 09:30 on the day: the day-before reminder has gone, the
      // hour-before one at 09:00 has too, but 09:45 is still to come.
      final List<ScheduledReminder> plan = EventReminderPlanner.plan(
        <SchoolEvent>[
          event(startMinute: 10 * 60, reminders: <int>[1440, 60, 15]),
        ],
        DateTime(2026, 7, 30, 9, 30),
      );

      expect(plan, hasLength(1));
      expect(plan.single.when, DateTime(2026, 7, 30, 9, 45));
    });

    test('a reminder exactly now is treated as past', () {
      final List<ScheduledReminder> plan = EventReminderPlanner.plan(
        <SchoolEvent>[event(startMinute: 10 * 60, reminders: <int>[60])],
        DateTime(2026, 7, 30, 9),
      );

      expect(
        plan,
        isEmpty,
        reason: 'scheduling it would make Android fire immediately',
      );
    });

    test('an event with no reminders contributes nothing', () {
      expect(
        EventReminderPlanner.plan(
          <SchoolEvent>[event(startMinute: 10 * 60)],
          DateTime(2026, 7, 28),
        ),
        isEmpty,
      );
    });

    test('orders across several events by time, not by event', () {
      final List<ScheduledReminder> plan = EventReminderPlanner.plan(
        <SchoolEvent>[
          event(
            id: 'later',
            date: DateTime(2026, 8, 5),
            startMinute: 9 * 60,
            reminders: <int>[1440],
          ),
          event(
            id: 'sooner',
            date: DateTime(2026, 8, 1),
            startMinute: 9 * 60,
            reminders: <int>[1440],
          ),
        ],
        DateTime(2026, 7, 28),
      );

      expect(
        plan.map((ScheduledReminder r) => r.when),
        <DateTime>[DateTime(2026, 7, 31, 9), DateTime(2026, 8, 4, 9)],
      );
    });

    test('an all-day event anchors at 08:00', () {
      final List<ScheduledReminder> plan = EventReminderPlanner.plan(
        <SchoolEvent>[event(reminders: <int>[1440])],
        DateTime(2026, 7, 28),
      );

      expect(plan.single.when, DateTime(2026, 7, 29, 8));
    });
  });

  group('ids and payloads', () {
    test('the same event and lead always give the same id', () {
      expect(
        EventReminderPlanner.reminderId('ev1', 60),
        EventReminderPlanner.reminderId('ev1', 60),
      );
    });

    test('different leads on one event give different ids', () {
      expect(
        EventReminderPlanner.reminderId('ev1', 60),
        isNot(EventReminderPlanner.reminderId('ev1', 1440)),
      );
    });

    test('different events give different ids', () {
      expect(
        EventReminderPlanner.reminderId('ev1', 60),
        isNot(EventReminderPlanner.reminderId('ev2', 60)),
      );
    });

    test('ids are deterministic, not seeded per process', () {
      // Hard-coded so a change of hashing algorithm is caught rather than
      // silently orphaning reminders scheduled by an earlier build. Object.hash
      // would fail this, since its seed is randomised per run.
      expect(EventReminderPlanner.reminderId('ev1', 60), 875322183);
      expect(EventReminderPlanner.reminderId('', 0), 503724647);
    });

    test('ids are non-negative, as Android requires', () {
      for (final String id in <String>['a', 'ev1', 'zzzz', '']) {
        for (final int lead in <int>[0, 60, 1440, 999999]) {
          expect(EventReminderPlanner.reminderId(id, lead), greaterThanOrEqualTo(0));
        }
      }
    });

    test('a payload round-trips back to its event id', () {
      final String payload = EventReminderPlanner.payloadFor('ev1', 1440);

      expect(payload, 'event:ev1:1440');
      expect(EventReminderPlanner.eventIdFromPayload(payload), 'ev1');
    });

    test('a foreign or malformed payload yields no event id', () {
      expect(EventReminderPlanner.eventIdFromPayload(null), isNull);
      expect(EventReminderPlanner.eventIdFromPayload('something-else'), isNull);
      expect(EventReminderPlanner.eventIdFromPayload('event:ev1'), isNull);
      expect(EventReminderPlanner.eventIdFromPayload('other:ev1:60'), isNull);
    });
  });

  group('describeLead', () {
    test('covers the offered lead times', () {
      expect(EventReminderPlanner.describeLead(0), 'Starting now');
      expect(EventReminderPlanner.describeLead(30), 'In 30 minutes');
      expect(EventReminderPlanner.describeLead(60), 'In 1 hour');
      expect(EventReminderPlanner.describeLead(120), 'In 2 hours');
      expect(EventReminderPlanner.describeLead(1440), 'Tomorrow');
      expect(EventReminderPlanner.describeLead(2880), 'In 2 days');
    });

    test('handles an odd lead without reading badly', () {
      expect(EventReminderPlanner.describeLead(90), 'In 1 h 30 m');
    });

    test('a negative lead reads as immediate rather than nonsense', () {
      expect(EventReminderPlanner.describeLead(-10), 'Starting now');
    });
  });

  group('notification text', () {
    test('a test names the class and subject', () {
      final ScheduledReminder reminder = EventReminderPlanner.plan(
        <SchoolEvent>[
          event(
            startMinute: 10 * 60,
            reminders: <int>[1440],
            classGroup: '8B',
            subject: 'Mathematics',
            location: 'R-12',
          ),
        ],
        DateTime(2026, 7, 28),
      ).single;

      expect(reminder.title, 'Unit test 2');
      expect(
        reminder.body,
        'Class test · Tomorrow · 10:00 · 8B · Mathematics · R-12',
      );
    });

    test('a fixture names the opponent and venue', () {
      final ScheduledReminder reminder = EventReminderPlanner.plan(
        <SchoolEvent>[
          event(
            category: SchoolEventCategory.match,
            title: 'Football friendly',
            startMinute: 15 * 60 + 30,
            reminders: <int>[120],
            opponent: "St. Xavier's",
            location: 'Main Field',
          ),
        ],
        DateTime(2026, 7, 30, 8),
      ).single;

      expect(reminder.title, 'Football friendly');
      expect(
        reminder.body,
        "Match · In 2 hours · 15:30 · vs St. Xavier's · Main Field",
      );
    });

    test('an all-day event omits a time it does not have', () {
      final ScheduledReminder reminder = EventReminderPlanner.plan(
        <SchoolEvent>[
          event(
            category: SchoolEventCategory.tournament,
            title: 'Inter-house athletics',
            reminders: <int>[1440],
          ),
        ],
        DateTime(2026, 7, 28),
      ).single;

      expect(reminder.body, 'Tournament · Tomorrow');
    });
  });
}
