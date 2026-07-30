import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/app_constants.dart';
import 'package:teachtrack/core/constants/hive_boxes.dart';
import 'package:teachtrack/core/errors/failures.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/features/timetable/data/local/timetable_local_data_source.dart';
import 'package:teachtrack/features/timetable/data/repositories/timetable_repository_impl.dart';
import 'package:teachtrack/features/timetable/domain/entities/class_session.dart';
import 'package:teachtrack/features/timetable/domain/entities/period.dart';
import 'package:teachtrack/features/timetable/domain/entities/scheduled_class.dart';
import 'package:teachtrack/features/timetable/domain/entities/timetable_entry.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';

void main() {
  late Directory tempDir;
  late TimetableLocalDataSource local;
  late SyncQueueService queue;
  late TimetableRepositoryImpl repository;
  late FakeClock clock;

  /// A Thursday.
  final DateTime thursday = DateTime(2026, 7, 30);

  const Period p1 = Period(
    id: 'p1',
    label: 'Period 1',
    startMinute: 480,
    endMinute: 525,
    sortOrder: 1,
  );
  const Period p2 = Period(
    id: 'p2',
    label: 'Period 2',
    startMinute: 525,
    endMinute: 570,
    sortOrder: 2,
  );

  TimetableEntry entry({
    String id = 'e1',
    int weekday = DateTime.thursday,
    String periodId = 'p1',
    String subject = 'Mathematics',
    String classGroup = '8B',
  }) =>
      TimetableEntry(
        id: id,
        weekday: weekday,
        periodId: periodId,
        subject: subject,
        classGroup: classGroup,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_timetable');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }

    local = TimetableLocalDataSource();
    await local.init();
    await local.putPeriods(<Period>[p1, p2]);

    clock = FakeClock(DateTime(2026, 7, 30, 10, 15));
    queue = SyncQueueService(
      box: await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations),
      clock: clock,
    );
    repository = TimetableRepositoryImpl(
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

  group('scheduleFor', () {
    test('joins entries with periods and orders them by period', () async {
      await local.putEntry(entry(id: 'late', periodId: 'p2'));
      await local.putEntry(entry(id: 'early', periodId: 'p1'));

      final List<ScheduledClass> schedule = repository.scheduleFor(thursday);

      expect(
        schedule.map((ScheduledClass c) => c.entry.id),
        <String>['early', 'late'],
      );
      expect(schedule.first.period.label, 'Period 1');
      expect(schedule.first.status, ClassSessionStatus.scheduled);
    });

    test('ignores entries belonging to another weekday', () async {
      await local.putEntry(entry(id: 'thu', weekday: DateTime.thursday));
      await local.putEntry(entry(id: 'fri', weekday: DateTime.friday));

      expect(repository.scheduleFor(thursday), hasLength(1));
    });

    test('skips an entry whose period no longer exists', () async {
      await local.putEntry(entry(id: 'orphan', periodId: 'deleted-period'));
      await local.putEntry(entry(id: 'ok', periodId: 'p1'));

      final List<ScheduledClass> schedule = repository.scheduleFor(thursday);

      expect(schedule.map((ScheduledClass c) => c.entry.id), <String>['ok']);
    });

    test('attaches a recorded session to the matching class', () async {
      final TimetableEntry e = entry();
      await local.putEntry(e);
      await repository.setSessionStatus(
        entry: e,
        date: thursday,
        status: ClassSessionStatus.completed,
      );

      final ScheduledClass item = repository.scheduleFor(thursday).single;

      expect(item.isCompleted, isTrue);
      expect(item.session?.updatedAt, clock.now());
    });

    test('a time-of-day component on the date does not affect the lookup',
        () async {
      await local.putEntry(entry());

      final List<ScheduledClass> schedule =
          repository.scheduleFor(DateTime(2026, 7, 30, 23, 59));

      expect(schedule, hasLength(1));
      expect(schedule.single.date, thursday);
    });
  });

  group('validateEntry', () {
    test('rejects a blank subject', () {
      final Failure? failure =
          repository.validateEntry(entry(subject: '  ')).failureOrNull;

      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).field, 'subject');
    });

    test('rejects a blank class', () {
      final Failure? failure =
          repository.validateEntry(entry(classGroup: '')).failureOrNull;

      expect((failure! as ValidationFailure).field, 'classGroup');
    });

    test('rejects an unknown period', () {
      final Failure? failure =
          repository.validateEntry(entry(periodId: 'nope')).failureOrNull;

      expect((failure! as ValidationFailure).field, 'periodId');
    });

    test('rejects a second entry in the same day and period', () async {
      await local.putEntry(entry(id: 'existing'));

      final Failure? failure = repository
          .validateEntry(entry(id: 'new', subject: 'Science'))
          .failureOrNull;

      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).field, 'periodId');
      expect(failure.message, contains('Mathematics'));
    });

    test('allows the same period on a different day', () async {
      await local.putEntry(entry(id: 'existing'));

      final result = repository
          .validateEntry(entry(id: 'new', weekday: DateTime.friday));

      expect(result.isOk, isTrue);
    });

    test('allows editing an entry without clashing with itself', () async {
      await local.putEntry(entry(id: 'e1'));

      final result =
          repository.validateEntry(entry(id: 'e1', subject: 'Algebra'));

      expect(result.isOk, isTrue);
    });

    test('rejects a day outside the teaching week', () {
      final Failure? failure = repository
          .validateEntry(entry(weekday: DateTime.sunday))
          .failureOrNull;

      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).field,
        'weekday',
        reason: 'the editor cannot display a Sunday entry',
      );
    });
  });

  group('replacePeriods', () {
    test('queues an update for survivors and a delete for removals', () async {
      final result = await repository.replacePeriods(<Period>[p1]);

      expect(result.isOk, isTrue);
      expect(repository.periods().map((Period p) => p.id), <String>['p1']);

      final Map<String, SyncOperationType> queued =
          <String, SyncOperationType>{
        for (final PendingOperation op in queue.dueOperations())
          op.entityId: op.operation,
      };

      expect(queued['p1'], SyncOperationType.update);
      expect(
        queued['p2'],
        SyncOperationType.delete,
        reason: 'a removed period must not linger in the cloud',
      );
    });

    test('refuses to leave the school with no periods at all', () async {
      final result = await repository.replacePeriods(<Period>[]);

      expect(result.isErr, isTrue);
      expect(repository.periods(), hasLength(2));
    });
  });

  group('upsertEntry', () {
    test('saves locally and queues a create for a new entry', () async {
      final result = await repository.upsertEntry(entry());

      expect(result.isOk, isTrue);
      expect(local.entryById('e1'), isNotNull);

      final PendingOperation op = queue.dueOperations().single;
      expect(op.entityType, SyncEntityTypes.timetableEntry);
      expect(op.entityId, 'e1');
      expect(op.operation, SyncOperationType.create);
      expect(op.payload['subject'], 'Mathematics');
    });

    test('queues an update when the entry already exists', () async {
      await local.putEntry(entry());

      await repository.upsertEntry(entry(subject: 'Algebra'));

      expect(queue.dueOperations().single.operation, SyncOperationType.update);
    });

    test('a rejected entry is neither saved nor queued', () async {
      final result = await repository.upsertEntry(entry(subject: ''));

      expect(result.isErr, isTrue);
      expect(local.entryById('e1'), isNull);
      expect(queue.pendingCount, 0);
    });
  });

  group('deleteEntry', () {
    test('removes locally and queues a delete', () async {
      await local.putEntry(entry());

      await repository.deleteEntry('e1');

      expect(local.entryById('e1'), isNull);
      expect(queue.dueOperations().single.operation, SyncOperationType.delete);
    });
  });

  group('setSessionStatus', () {
    test('uses a deterministic id built from the date and entry', () async {
      final TimetableEntry e = entry();

      await repository.setSessionStatus(
        entry: e,
        date: thursday,
        status: ClassSessionStatus.completed,
      );

      expect(local.sessionById('2026-07-30_e1'), isNotNull);
      expect(queue.dueOperations().single.entityId, '2026-07-30_e1');
    });

    test('marking the same class twice coalesces into one remote write',
        () async {
      final TimetableEntry e = entry();

      await repository.setSessionStatus(
        entry: e,
        date: thursday,
        status: ClassSessionStatus.completed,
      );
      await repository.setSessionStatus(
        entry: e,
        date: thursday,
        status: ClassSessionStatus.cancelled,
      );

      expect(queue.pendingCount, 1, reason: 'one Firestore write, not two');
      expect(
        local.sessionById('2026-07-30_e1')?.status,
        ClassSessionStatus.cancelled,
      );
    });

    test('clearing a status deletes the record and queues a delete', () async {
      final TimetableEntry e = entry();
      await local.putSession(
        ClassSession(
          id: ClassSession.buildId(thursday, e.id),
          entryId: e.id,
          date: thursday,
          status: ClassSessionStatus.completed,
        ),
      );

      await repository.setSessionStatus(
        entry: e,
        date: thursday,
        status: ClassSessionStatus.scheduled,
      );

      expect(local.sessionById('2026-07-30_e1'), isNull);
      expect(queue.dueOperations().single.operation, SyncOperationType.delete);
    });

    test('records the same class separately on different dates', () async {
      final TimetableEntry e = entry();

      await repository.setSessionStatus(
        entry: e,
        date: thursday,
        status: ClassSessionStatus.completed,
      );
      await repository.setSessionStatus(
        entry: e,
        date: DateTime(2026, 8, 6),
        status: ClassSessionStatus.completed,
      );

      expect(local.sessionById('2026-07-30_e1'), isNotNull);
      expect(local.sessionById('2026-08-06_e1'), isNotNull);
      expect(queue.pendingCount, 2);
    });
  });

  group('pruneSessionsBefore', () {
    test('drops only sessions older than the cutoff', () async {
      final TimetableEntry e = entry();
      for (final DateTime date in <DateTime>[
        DateTime(2026, 5, 1),
        DateTime(2026, 7, 1),
        thursday,
      ]) {
        await local.putSession(
          ClassSession(
            id: ClassSession.buildId(date, e.id),
            entryId: e.id,
            date: date,
            status: ClassSessionStatus.completed,
          ),
        );
      }

      final int removed =
          await local.pruneSessionsBefore(DateTime(2026, 7, 1));

      expect(removed, 1);
      expect(local.sessionsBox.length, 2);
    });
  });
}
