import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/app_constants.dart';
import 'package:teachtrack/core/constants/hive_boxes.dart';
import 'package:teachtrack/core/errors/failures.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/features/timetable/data/local/override_local_data_source.dart';
import 'package:teachtrack/features/timetable/data/local/subject_store.dart';
import 'package:teachtrack/features/timetable/data/local/timetable_local_data_source.dart';
import 'package:teachtrack/features/timetable/data/repositories/override_repository_impl.dart';
import 'package:teachtrack/features/timetable/data/repositories/timetable_repository_impl.dart';
import 'package:teachtrack/features/timetable/domain/entities/class_session.dart';
import 'package:teachtrack/features/timetable/domain/entities/period.dart';
import 'package:teachtrack/features/timetable/domain/entities/schedule_override.dart';
import 'package:teachtrack/features/timetable/domain/entities/scheduled_class.dart';
import 'package:teachtrack/features/timetable/domain/entities/timetable_entry.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';

void main() {
  late Directory tempDir;
  late TimetableLocalDataSource timetableLocal;
  late OverrideLocalDataSource overrideLocal;
  late SyncQueueService queue;
  late OverrideRepositoryImpl overrides;
  late TimetableRepositoryImpl timetable;
  late FakeClock clock;

  /// A Thursday, and the Friday after it.
  final DateTime thursday = DateTime(2026, 7, 30);
  final DateTime friday = DateTime(2026, 7, 31);

  const Period p1 = Period(
    id: 'p1',
    label: 'Period 1',
    startMinute: 480,
    endMinute: 525,
    sortOrder: 1,
  );

  OverrideSlot slot({
    String id = 's1',
    DateTime? date,
    int startMinute = 9 * 60,
    int? endMinute = 11 * 60,
    String title = 'Mathematics paper 1',
    String classGroup = '8B',
    String location = 'Hall A',
    bool isInvigilating = false,
    bool isMySubject = false,
  }) =>
      OverrideSlot(
        id: id,
        date: date ?? thursday,
        startMinute: startMinute,
        endMinute: endMinute,
        title: title,
        classGroup: classGroup,
        location: location,
        isInvigilating: isInvigilating,
        isMySubject: isMySubject,
      );

  ScheduleOverride override({
    String id = 'ov1',
    String name = 'Half-yearly exams',
    ScheduleOverrideKind kind = ScheduleOverrideKind.exam,
    DateTime? startDate,
    DateTime? endDate,
    List<OverrideSlot> slots = const <OverrideSlot>[],
  }) =>
      ScheduleOverride(
        id: id,
        name: name,
        kind: kind,
        startDate: startDate ?? thursday,
        endDate: endDate ?? friday,
        slots: slots,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_overrides');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }

    timetableLocal = TimetableLocalDataSource();
    await timetableLocal.init();
    await timetableLocal.putPeriods(<Period>[p1]);

    overrideLocal = OverrideLocalDataSource();
    await overrideLocal.init();

    clock = FakeClock(DateTime(2026, 7, 30, 8));
    queue = SyncQueueService(
      box: await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations),
      clock: clock,
    );
    overrides = OverrideRepositoryImpl(
      local: overrideLocal,
      syncQueue: queue,
      clock: clock,
    );
    timetable = TimetableRepositoryImpl(
      local: timetableLocal,
      subjects: SubjectStore(
        settingsBox: await Hive.openBox<dynamic>(HiveBoxes.settings),
      ),
      syncQueue: queue,
      overrides: overrideLocal,
      clock: clock,
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('covers', () {
    test('is inclusive at both ends and ignores any time component', () {
      final ScheduleOverride o = override();

      expect(o.covers(thursday), isTrue);
      expect(o.covers(friday), isTrue);
      expect(o.covers(DateTime(2026, 7, 31, 23, 59)), isTrue);
      expect(o.covers(DateTime(2026, 7, 29)), isFalse);
      expect(o.covers(DateTime(2026, 8, 1)), isFalse);
    });

    test('dayCount counts both ends', () {
      expect(override().dayCount, 2);
      expect(override(endDate: thursday).dayCount, 1);
    });
  });

  group('dates', () {
    test('lists every date in the range, in order', () {
      expect(
        override(endDate: DateTime(2026, 8, 2)).dates,
        <DateTime>[
          DateTime(2026, 7, 30),
          DateTime(2026, 7, 31),
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 2),
        ],
      );
    });

    test('a single-day override lists one date', () {
      expect(override(endDate: thursday).dates, <DateTime>[thursday]);
    });
  });

  group('slotsWithDayCopied', () {
    int nextId = 0;
    String idFor(OverrideSlot _) => 'copy-${nextId++}';

    setUp(() => nextId = 0);

    test('duplicates a day onto another, keeping what was already there', () {
      final ScheduleOverride source = override(
        slots: <OverrideSlot>[
          slot(id: 'a', title: 'Maths'),
          slot(
            id: 'b',
            startMinute: 13 * 60,
            endMinute: 15 * 60,
            title: 'Science',
          ),
          slot(id: 'existing', date: friday, title: 'Already on Friday'),
        ],
      );

      final List<OverrideSlot> next = source.slotsWithDayCopied(
        from: thursday,
        to: friday,
        idFor: idFor,
      );

      expect(next, hasLength(5));
      final List<OverrideSlot> fridaySlots =
          source.copyWith(slots: next).slotsOn(friday);

      // Compared as a set: two of these start at 09:00, and Dart's sort makes no
      // stability guarantee, so asserting an exact order would be testing the
      // sort implementation rather than the copy.
      expect(fridaySlots, hasLength(3));
      expect(
        fridaySlots.map((OverrideSlot s) => s.title).toSet(),
        <String>{'Maths', 'Science', 'Already on Friday'},
        reason: 'the copies were added and nothing was replaced',
      );
    });

    test('copies carry new ids so sessions cannot be shared', () {
      final ScheduleOverride source =
          override(slots: <OverrideSlot>[slot(id: 'a')]);

      final List<OverrideSlot> next = source.slotsWithDayCopied(
        from: thursday,
        to: friday,
        idFor: idFor,
      );

      expect(next.map((OverrideSlot s) => s.id).toSet(), hasLength(2));
      expect(next.last.id, 'copy-0');
    });

    test('copies every field except the date and id', () {
      final ScheduleOverride source = override(
        slots: <OverrideSlot>[
          slot(isInvigilating: true, isMySubject: true, location: 'Hall B'),
        ],
      );

      final OverrideSlot copy = source
          .slotsWithDayCopied(from: thursday, to: friday, idFor: idFor)
          .last;

      expect(copy.date, friday);
      expect(copy.title, 'Mathematics paper 1');
      expect(copy.classGroup, '8B');
      expect(copy.location, 'Hall B');
      expect(copy.isInvigilating, isTrue);
      expect(copy.isMySubject, isTrue);
      expect(copy.startMinute, 9 * 60);
      expect(copy.endMinute, 11 * 60);
    });

    test('refuses a target outside the range', () {
      final ScheduleOverride source =
          override(slots: <OverrideSlot>[slot()]);

      expect(
        source.slotsWithDayCopied(
          from: thursday,
          to: DateTime(2026, 8, 20),
          idFor: idFor,
        ),
        source.slots,
      );
    });

    test('copying a day onto itself changes nothing', () {
      final ScheduleOverride source =
          override(slots: <OverrideSlot>[slot()]);

      expect(
        source.slotsWithDayCopied(
          from: thursday,
          to: thursday,
          idFor: idFor,
        ),
        source.slots,
      );
    });

    test('copying an empty day changes nothing', () {
      final ScheduleOverride source =
          override(slots: <OverrideSlot>[slot(date: friday)]);

      expect(
        source.slotsWithDayCopied(from: thursday, to: friday, idFor: idFor),
        source.slots,
      );
    });

    test('the result still passes validation', () async {
      final ScheduleOverride source =
          override(slots: <OverrideSlot>[slot(), slot(id: 'b', title: 'Two')]);

      final ScheduleOverride copied = source.copyWith(
        slots: source.slotsWithDayCopied(
          from: thursday,
          to: friday,
          idFor: idFor,
        ),
      );

      expect(
        overrides.validate(copied).isOk,
        isTrue,
        reason: 'no duplicate ids, and every copy lands inside the range',
      );
    });
  });

  group('validate', () {
    test('rejects a blank name', () {
      expect(
        (overrides.validate(override(name: '  ')).failureOrNull!
                as ValidationFailure)
            .field,
        'name',
      );
    });

    test('rejects an inverted range', () {
      final Failure? failure = overrides
          .validate(override(startDate: friday, endDate: thursday))
          .failureOrNull;

      expect((failure! as ValidationFailure).field, 'endDate');
    });

    test('rejects a range overlapping an existing override', () async {
      await overrides.upsert(override());

      final Failure? failure = overrides
          .validate(
            override(
              id: 'ov2',
              name: 'Sports day',
              startDate: friday,
              endDate: DateTime(2026, 8, 3),
            ),
          )
          .failureOrNull;

      expect(failure, isA<ValidationFailure>());
      expect(failure!.message, contains('Half-yearly exams'));
    });

    test('lets an override be edited without clashing with itself', () async {
      await overrides.upsert(override());

      expect(overrides.validate(override(name: 'Renamed')).isOk, isTrue);
    });

    test('rejects a sitting outside the range', () {
      final Failure? failure = overrides
          .validate(
            override(slots: <OverrideSlot>[slot(date: DateTime(2026, 8, 5))]),
          )
          .failureOrNull;

      expect((failure! as ValidationFailure).field, 'slots');
    });

    test('rejects sittings on a holiday', () {
      final Failure? failure = overrides
          .validate(
            override(
              kind: ScheduleOverrideKind.holiday,
              slots: <OverrideSlot>[slot()],
            ),
          )
          .failureOrNull;

      expect((failure! as ValidationFailure).field, 'slots');
    });

    test('rejects a sitting that ends before it starts', () {
      expect(
        overrides
            .validate(
              override(
                slots: <OverrideSlot>[
                  slot(startMinute: 600, endMinute: 600),
                ],
              ),
            )
            .isErr,
        isTrue,
      );
    });

    test('accepts a sitting with no end time', () {
      expect(
        overrides
            .validate(override(slots: <OverrideSlot>[slot(endMinute: null)]))
            .isOk,
        isTrue,
      );
    });
  });

  group('upsert', () {
    test('normalises dates before validating, so a timestamp still fits', () async {
      final result = await overrides.upsert(
        override(
          startDate: DateTime(2026, 7, 30, 14, 30),
          endDate: DateTime(2026, 7, 31, 9),
          slots: <OverrideSlot>[slot(date: DateTime(2026, 7, 30, 23, 59))],
        ),
      );

      expect(result.isOk, isTrue);
      final ScheduleOverride stored = overrides.byId('ov1')!;
      expect(stored.startDate, thursday);
      expect(stored.slots.single.date, thursday);
    });

    test('queues a create then coalesces further edits', () async {
      await overrides.upsert(override());
      await overrides.upsert(override(name: 'Renamed'));

      final PendingOperation op = queue.dueOperations().single;
      expect(op.entityType, SyncEntityTypes.scheduleOverride);
      expect(op.payload['name'], 'Renamed');
    });

    test('an override survives a real Hive reopen, slots included', () async {
      await overrides.upsert(
        override(
          slots: <OverrideSlot>[
            slot(isInvigilating: true, isMySubject: true),
            slot(
              id: 's2',
              date: friday,
              startMinute: 13 * 60,
              endMinute: 15 * 60,
              title: 'Science',
            ),
          ],
        ),
      );

      await overrideLocal.close();
      await overrideLocal.init();

      final ScheduleOverride stored = overrideLocal.byId('ov1')!;
      expect(stored.kind, ScheduleOverrideKind.exam);
      expect(stored.slots, hasLength(2));
      expect(stored.slots.first.isInvigilating, isTrue);
      expect(stored.slots.first.isMySubject, isTrue);
      expect(stored.slots.first.location, 'Hall A');
      expect(stored.slots.last.title, 'Science');
    });
  });

  group('day resolution', () {
    test('a normal day still uses the weekly timetable', () async {
      await timetableLocal.putEntry(
        const TimetableEntry(
          id: 'e1',
          weekday: DateTime.thursday,
          periodId: 'p1',
          subject: 'Mathematics',
          classGroup: '8B',
        ),
      );

      final List<ScheduledClass> day = timetable.scheduleFor(thursday);

      expect(day.single.entry.subject, 'Mathematics');
      expect(day.single.isFromOverride, isFalse);
      expect(timetable.overrideFor(thursday), isNull);
    });

    test('an exam day replaces the timetable with its sittings', () async {
      await timetableLocal.putEntry(
        const TimetableEntry(
          id: 'e1',
          weekday: DateTime.thursday,
          periodId: 'p1',
          subject: 'Mathematics',
          classGroup: '8B',
        ),
      );
      await overrides.upsert(
        override(slots: <OverrideSlot>[slot(isInvigilating: true)]),
      );

      final List<ScheduledClass> day = timetable.scheduleFor(thursday);

      expect(day, hasLength(1));
      expect(day.single.entry.subject, 'Mathematics paper 1');
      expect(day.single.entry.room, 'Hall A');
      expect(day.single.isFromOverride, isTrue);
      expect(day.single.isInvigilating, isTrue);
      expect(day.single.period.startMinute, 9 * 60);
      expect(day.single.period.endMinute, 11 * 60);
      expect(timetable.overrideFor(thursday)?.name, 'Half-yearly exams');
    });

    test('a holiday empties the day entirely', () async {
      await timetableLocal.putEntry(
        const TimetableEntry(
          id: 'e1',
          weekday: DateTime.thursday,
          periodId: 'p1',
          subject: 'Mathematics',
          classGroup: '8B',
        ),
      );
      await overrides.upsert(
        override(kind: ScheduleOverrideKind.holiday, name: 'Diwali break'),
      );

      expect(
        timetable.scheduleFor(thursday),
        isEmpty,
        reason: 'better than the normal day with everything cancelled',
      );
      expect(timetable.overrideFor(thursday)?.isHoliday, isTrue);
    });

    test('only that date\'s sittings appear, ordered by start time', () async {
      await overrides.upsert(
        override(
          slots: <OverrideSlot>[
            slot(
              id: 'late',
              startMinute: 13 * 60,
              endMinute: 15 * 60,
              title: 'Afternoon',
            ),
            slot(id: 'early', startMinute: 9 * 60, title: 'Morning'),
            slot(id: 'other', date: friday, title: 'Friday paper'),
          ],
        ),
      );

      final List<ScheduledClass> day = timetable.scheduleFor(thursday);

      expect(
        day.map((ScheduledClass c) => c.entry.subject),
        <String>['Morning', 'Afternoon'],
      );
    });

    test('a day inside the range with no sittings is empty', () async {
      await overrides.upsert(override(slots: <OverrideSlot>[slot()]));

      expect(timetable.scheduleFor(friday), isEmpty);
      expect(timetable.overrideFor(friday), isNotNull);
    });

    test('a sitting with no end time is given a nominal hour', () async {
      await overrides.upsert(
        override(slots: <OverrideSlot>[slot(endMinute: null)]),
      );

      final ScheduledClass sitting = timetable.scheduleFor(thursday).single;

      expect(sitting.period.endMinute, sitting.period.startMinute + 60);
    });

    test('marking a sitting uses an id that cannot collide with a lesson',
        () async {
      await overrides.upsert(override(slots: <OverrideSlot>[slot()]));
      final ScheduledClass sitting = timetable.scheduleFor(thursday).single;

      await timetable.setSessionStatus(
        entry: sitting.entry,
        date: thursday,
        status: ClassSessionStatus.completed,
      );

      expect(sitting.entry.id, 'slot:s1');
      expect(timetableLocal.sessionById('2026-07-30_slot:s1'), isNotNull);
      expect(
        timetable.scheduleFor(thursday).single.isCompleted,
        isTrue,
        reason: 'duty is markable the same way a lesson is',
      );
    });

    test('removing the override restores the normal timetable', () async {
      await timetableLocal.putEntry(
        const TimetableEntry(
          id: 'e1',
          weekday: DateTime.thursday,
          periodId: 'p1',
          subject: 'Mathematics',
          classGroup: '8B',
        ),
      );
      await overrides.upsert(override(slots: <OverrideSlot>[slot()]));
      expect(timetable.scheduleFor(thursday).single.isFromOverride, isTrue);

      await overrides.delete('ov1');

      expect(timetable.scheduleFor(thursday).single.entry.subject, 'Mathematics');
    });

    test('with no override data source at all, days fall back cleanly', () async {
      final TimetableRepositoryImpl plain = TimetableRepositoryImpl(
        local: timetableLocal,
        subjects: SubjectStore(settingsBox: Hive.box<dynamic>(HiveBoxes.settings)),
        syncQueue: queue,
        clock: clock,
      );
      await overrides.upsert(override(kind: ScheduleOverrideKind.holiday));

      expect(plain.overrideFor(thursday), isNull);
      expect(plain.scheduleFor(thursday), isEmpty, reason: 'no entries exist');
    });
  });

  group('actionability', () {
    test('a sitting you invigilate or own can be marked', () async {
      await overrides.upsert(
        override(
          slots: <OverrideSlot>[
            slot(id: 'duty', isInvigilating: true),
            slot(
              id: 'mine',
              startMinute: 13 * 60,
              endMinute: 15 * 60,
              isMySubject: true,
            ),
          ],
        ),
      );

      expect(
        timetable
            .scheduleFor(thursday)
            .every((ScheduledClass c) => c.isActionable),
        isTrue,
      );
    });

    test('somebody else\'s paper is shown but not markable', () async {
      await overrides.upsert(override(slots: <OverrideSlot>[slot()]));

      final ScheduledClass sitting = timetable.scheduleFor(thursday).single;

      expect(sitting.isFromOverride, isTrue);
      expect(
        sitting.isActionable,
        isFalse,
        reason: 'the hall is in use, but it is not this teacher\'s to account for',
      );
    });
  });

  group('clearAllData', () {
    test('removes overrides too, queueing a delete for each', () async {
      await overrides.upsert(override(slots: <OverrideSlot>[slot()]));

      final result = await timetable.clearAllData();

      expect(result.valueOrNull, 1);
      expect(overrides.all(), isEmpty);
      expect(
        queue.pendingCount,
        0,
        reason: 'the queued create coalesces with the delete and both drop — the '
            'server never saw this override, so there is nothing to tell it',
      );
    });

    test('an already-synced override queues a delete when cleared', () async {
      // Written straight to the box so nothing is queued, mimicking an override
      // that has already been pushed upstream.
      await overrideLocal.put(override(slots: <OverrideSlot>[slot()]));

      await timetable.clearAllData();

      final PendingOperation op = queue.dueOperations().single;
      expect(op.entityType, SyncEntityTypes.scheduleOverride);
      expect(op.operation, SyncOperationType.delete);
    });
  });

  group('upcoming', () {
    test('keeps an override that is still running and drops finished ones',
        () async {
      await overrides.upsert(
        override(
          id: 'past',
          name: 'Last term',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 6, 5),
        ),
      );
      await overrides.upsert(override());

      expect(
        overrides.upcoming(from: thursday).map((ScheduleOverride o) => o.id),
        <String>['ov1'],
      );
    });
  });
}
