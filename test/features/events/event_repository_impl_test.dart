import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/app_constants.dart';
import 'package:teachtrack/core/constants/hive_boxes.dart';
import 'package:teachtrack/core/errors/failures.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/features/events/data/local/event_local_data_source.dart';
import 'package:teachtrack/features/events/data/repositories/event_repository_impl.dart';
import 'package:teachtrack/features/events/domain/entities/school_event.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';

void main() {
  late Directory tempDir;
  late EventLocalDataSource local;
  late SyncQueueService queue;
  late EventRepositoryImpl repository;
  late FakeClock clock;

  /// A Thursday.
  final DateTime today = DateTime(2026, 7, 30);

  SchoolEvent event({
    String id = 'ev1',
    DateTime? date,
    SchoolEventCategory category = SchoolEventCategory.classTest,
    String title = 'Unit test 2',
    int? startMinute,
    int? endMinute,
    List<int> reminders = const <int>[],
  }) =>
      SchoolEvent(
        id: id,
        date: date ?? today,
        category: category,
        title: title,
        startMinute: startMinute,
        endMinute: endMinute,
        reminderLeadMinutes: reminders,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_events');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }

    local = EventLocalDataSource();
    await local.init();

    clock = FakeClock(DateTime(2026, 7, 30, 9));
    queue = SyncQueueService(
      box: await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations),
      clock: clock,
    );
    repository = EventRepositoryImpl(
      local: local,
      syncQueue: queue,
      clock: clock,
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('validate', () {
    test('rejects a blank title', () {
      final Failure? failure =
          repository.validate(event(title: '   ')).failureOrNull;

      expect((failure! as ValidationFailure).field, 'title');
    });

    test('rejects an end time with no start time', () {
      final Failure? failure =
          repository.validate(event(endMinute: 600)).failureOrNull;

      expect((failure! as ValidationFailure).field, 'startMinute');
    });

    test('rejects an end time at or before the start', () {
      final Failure? failure = repository
          .validate(event(startMinute: 600, endMinute: 600))
          .failureOrNull;

      expect((failure! as ValidationFailure).field, 'endMinute');
    });

    test('rejects a start time outside the day', () {
      expect(repository.validate(event(startMinute: 1440)).isErr, isTrue);
    });

    test('rejects an end time outside the day', () {
      expect(
        repository.validate(event(startMinute: 600, endMinute: 2000)).isErr,
        isTrue,
        reason: 'DayTime.format would silently clamp it to 23:59',
      );
    });

    test('accepts an all-day event', () {
      expect(repository.validate(event()).isOk, isTrue);
    });
  });

  group('upsert', () {
    test('saves and queues a create', () async {
      await repository.upsert(event());

      final PendingOperation op = queue.dueOperations().single;
      expect(op.operation, SyncOperationType.create);
      expect(op.entityType, SyncEntityTypes.schoolEvent);
      expect(op.payload['title'], 'Unit test 2');
    });

    test('editing before the create has synced stays one create', () async {
      await repository.upsert(event());
      await repository.upsert(event(title: 'Unit test 2 (revised)'));

      final PendingOperation op = queue.dueOperations().single;
      expect(
        op.operation,
        SyncOperationType.create,
        reason: 'the outbox coalesces create+update — the server has never seen '
            'this event, so it is still a create',
      );
      expect(op.payload['title'], 'Unit test 2 (revised)');
      expect(queue.pendingCount, 1);
    });

    test('editing an already-synced event queues an update', () async {
      // Seeded straight to the box so nothing is queued, mimicking an event that
      // has already been pushed.
      await local.put(event());

      await repository.upsert(event(title: 'Unit test 2 (revised)'));

      expect(queue.dueOperations().single.operation, SyncOperationType.update);
    });

    test('trims the title and strips any time from the date', () async {
      await repository.upsert(
        event(title: '  Unit test  ', date: DateTime(2026, 7, 30, 15, 42)),
      );

      final SchoolEvent stored = repository.byId('ev1')!;
      expect(stored.title, 'Unit test');
      expect(stored.date, today);
    });

    test('stamps updatedAt from the clock', () async {
      await repository.upsert(event());

      expect(repository.byId('ev1')?.updatedAt, clock.now());
    });

    test('a rejected event is neither saved nor queued', () async {
      final result = await repository.upsert(event(title: ''));

      expect(result.isErr, isTrue);
      expect(repository.byId('ev1'), isNull);
      expect(queue.pendingCount, 0);
    });
  });

  group('upcoming', () {
    test('excludes past events and orders soonest first', () async {
      await repository.upsert(
        event(id: 'past', date: DateTime(2026, 7, 20)),
      );
      await repository.upsert(
        event(id: 'later', date: DateTime(2026, 8, 10)),
      );
      await repository.upsert(event(id: 'today', date: today));

      final List<SchoolEvent> upcoming = repository.upcoming(from: today);

      expect(
        upcoming.map((SchoolEvent e) => e.id),
        <String>['today', 'later'],
      );
    });

    test('includes an event on the from-date itself', () async {
      await repository.upsert(event(date: today));

      expect(
        repository.upcoming(from: DateTime(2026, 7, 30, 23, 59)),
        hasLength(1),
        reason: 'a time component must not exclude today',
      );
    });

    test('respects the day window', () async {
      await repository.upsert(
        event(id: 'far', date: DateTime(2026, 12, 1)),
      );

      expect(repository.upcoming(from: today, days: 7), isEmpty);
      expect(repository.upcoming(from: today, days: 365), hasLength(1));
    });

    test('all-day events sort before timed ones on the same date', () async {
      await repository.upsert(
        event(id: 'timed', date: today, startMinute: 9 * 60),
      );
      await repository.upsert(event(id: 'allday', date: today));

      expect(
        repository.upcoming(from: today).map((SchoolEvent e) => e.id),
        <String>['allday', 'timed'],
      );
    });
  });

  group('forDate', () {
    test('matches by calendar day, ignoring any time component', () async {
      await repository.upsert(event(date: today));

      expect(repository.forDate(DateTime(2026, 7, 30, 18)), hasLength(1));
      expect(repository.forDate(DateTime(2026, 7, 31)), isEmpty);
    });
  });

  group('delete', () {
    test('removes the event and queues a delete', () async {
      await local.put(event());

      await repository.delete('ev1');

      expect(repository.byId('ev1'), isNull);
      expect(queue.dueOperations().single.operation, SyncOperationType.delete);
    });

    test('deleting something that is not there queues nothing', () async {
      final result = await repository.delete('never-existed');

      expect(result.isOk, isTrue);
      expect(
        queue.pendingCount,
        0,
        reason: 'a no-op must not spend a remote write',
      );
    });
  });

  group('reminders', () {
    test('each category carries its own sensible defaults', () {
      expect(
        SchoolEventCategory.classTest.defaultReminderLeadMinutes,
        <int>[1440, 60],
      );
      expect(
        SchoolEventCategory.tournament.defaultReminderLeadMinutes,
        <int>[2880, 1440, 120],
      );
      expect(
        SchoolEventCategory.meeting.defaultReminderLeadMinutes,
        <int>[30],
      );
    });

    test('reminder times are computed back from the start time', () {
      final SchoolEvent e = event(
        startMinute: 10 * 60,
        reminders: <int>[1440, 60],
      );

      expect(
        e.reminderTimes(),
        <DateTime>[
          DateTime(2026, 7, 29, 10),
          DateTime(2026, 7, 30, 9),
        ],
      );
    });

    test('an all-day event anchors its reminders at 08:00', () {
      final SchoolEvent e = event(reminders: <int>[1440]);

      expect(
        e.reminderTimes().single,
        DateTime(2026, 7, 29, 8),
        reason: 'a day-before reminder at midnight would be useless',
      );
    });

    test('no reminders means no times', () {
      expect(event().reminderTimes(), isEmpty);
      expect(event().hasReminders, isFalse);
    });

    test('a negative lead is rejected', () {
      expect(
        repository.validate(event(reminders: <int>[-30])).isErr,
        isTrue,
      );
    });
  });

  group('durability', () {
    test('an event survives a real Hive reopen', () async {
      await repository.upsert(
        event(
          category: SchoolEventCategory.tournament,
          title: 'Inter-house football',
          startMinute: 9 * 60,
          endMinute: 12 * 60,
          reminders: <int>[1440, 120],
        ),
      );

      // Closing and reopening forces the TypeAdapter to actually run — a
      // non-lazy box would otherwise serve the original instance from memory.
      await local.close();
      await local.init();

      final SchoolEvent stored = local.byId('ev1')!;
      expect(stored.category, SchoolEventCategory.tournament);
      expect(stored.title, 'Inter-house football');
      expect(stored.startMinute, 9 * 60);
      expect(stored.endMinute, 12 * 60);
      expect(stored.reminderLeadMinutes, <int>[1440, 120]);
      expect(stored.date, today);
    });
  });

  group('presentation helpers', () {
    test('a fixture describes itself by opponent and venue', () {
      // Not const: DateTime has no const constructor.
      final SchoolEvent fixture = SchoolEvent(
        id: 'f1',
        date: DateTime(2026, 8, 1),
        category: SchoolEventCategory.match,
        title: 'Football friendly',
        opponent: "St. Xavier's",
        location: 'Main Field',
        classGroup: 'ignored',
      );

      expect(fixture.subtitle, "vs St. Xavier's · Main Field");
      expect(fixture.category.isFixture, isTrue);
    });

    test('a test describes itself by class and subject', () {
      final SchoolEvent test = SchoolEvent(
        id: 't1',
        date: DateTime(2026, 8, 1),
        category: SchoolEventCategory.classTest,
        title: 'Unit test',
        classGroup: '8B',
        subject: 'Mathematics',
        location: 'R-12',
      );

      expect(test.subtitle, '8B · Mathematics · R-12');
      expect(test.category.isFixture, isFalse);
    });

    test('the time label covers all three shapes', () {
      expect(event().timeLabel, 'All day');
      expect(event(startMinute: 9 * 60).timeLabel, '09:00');
      expect(
        event(startMinute: 9 * 60, endMinute: 10 * 60 + 30).timeLabel,
        '09:00 – 10:30',
      );
    });
  });
}
