import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/hive_boxes.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/features/backup/data/backup_repository_impl.dart';
import 'package:teachtrack/features/backup/domain/backup_payload.dart';
import 'package:teachtrack/features/events/data/local/event_local_data_source.dart';
import 'package:teachtrack/features/events/domain/entities/school_event.dart';
import 'package:teachtrack/features/timetable/data/local/override_local_data_source.dart';
import 'package:teachtrack/features/timetable/data/local/subject_store.dart';
import 'package:teachtrack/features/timetable/data/local/timetable_local_data_source.dart';
import 'package:teachtrack/features/timetable/data/repositories/override_repository_impl.dart';
import 'package:teachtrack/features/timetable/data/repositories/timetable_repository_impl.dart';
import 'package:teachtrack/features/timetable/domain/entities/class_session.dart';
import 'package:teachtrack/features/timetable/domain/entities/period.dart';
import 'package:teachtrack/features/timetable/domain/entities/schedule_override.dart';
import 'package:teachtrack/features/timetable/domain/entities/timetable_entry.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> settings;
  late SubjectStore subjects;
  late TimetableLocalDataSource timetableLocal;
  late EventLocalDataSource eventLocal;
  late OverrideLocalDataSource overrideLocal;
  late TimetableRepositoryImpl timetable;
  late OverrideRepositoryImpl overrides;
  late SyncQueueService queue;
  late BackupRepositoryImpl backup;
  late FakeClock clock;

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

  const TimetableEntry entry = TimetableEntry(
    id: 'e1',
    weekday: DateTime.thursday,
    periodId: 'p1',
    subject: 'Mathematics',
    classGroup: '8B',
    room: 'R-12',
    teacherId: 't1',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_backup');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }

    settings = await Hive.openBox<dynamic>(HiveBoxes.settings);
    subjects = SubjectStore(settingsBox: settings);

    timetableLocal = TimetableLocalDataSource();
    await timetableLocal.init();
    eventLocal = EventLocalDataSource();
    await eventLocal.init();
    overrideLocal = OverrideLocalDataSource();
    await overrideLocal.init();

    clock = FakeClock(DateTime(2026, 7, 30, 9));
    queue = SyncQueueService(
      box: await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations),
      clock: clock,
    );
    timetable = TimetableRepositoryImpl(
      local: timetableLocal,
      subjects: subjects,
      syncQueue: queue,
      overrides: overrideLocal,
      clock: clock,
    );
    overrides = OverrideRepositoryImpl(
      local: overrideLocal,
      syncQueue: queue,
      clock: clock,
    );
    backup = BackupRepositoryImpl(
      settingsBox: settings,
      subjects: subjects,
      timetableLocal: timetableLocal,
      eventLocal: eventLocal,
      overrideLocal: overrideLocal,
      timetable: timetable,
      overrides: overrides,
      syncQueue: queue,
      clock: clock,
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Fills the device with one of everything.
  Future<void> seedEverything() async {
    await settings.put(
      SettingsKeys.teacherProfile,
      jsonEncode(<String, dynamic>{
        'id': 't1',
        'fullName': 'Anita Rao',
        'classTeacherOf': '8B',
      }),
    );
    await subjects.seedIfEmpty();
    await timetableLocal.putPeriods(<Period>[p1, p2]);
    await timetableLocal.putEntry(entry);
    await timetableLocal.putSession(
      ClassSession(
        id: ClassSession.buildId(thursday, 'e1'),
        entryId: 'e1',
        date: thursday,
        status: ClassSessionStatus.completed,
        note: 'Finished chapter 4',
      ),
    );
    await eventLocal.put(
      SchoolEvent(
        id: 'ev1',
        date: DateTime(2026, 8, 5),
        category: SchoolEventCategory.classTest,
        title: 'Unit test 2',
        startMinute: 600,
        reminderLeadMinutes: const <int>[1440],
      ),
    );
    await overrideLocal.put(
      ScheduleOverride(
        id: 'ov1',
        name: 'Half-yearly exams',
        kind: ScheduleOverrideKind.exam,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 3),
        slots: <OverrideSlot>[
          OverrideSlot(
            id: 's1',
            date: DateTime(2026, 9, 1),
            startMinute: 540,
            endMinute: 660,
            title: 'Mathematics paper 1',
            isInvigilating: true,
          ),
        ],
      ),
    );
  }

  group('payload encoding', () {
    test('a full snapshot survives encode and decode', () async {
      await seedEverything();

      final BackupPayload restored =
          BackupPayload.decode(backup.snapshot().encode());

      expect(restored.version, BackupPayload.currentVersion);
      expect(restored.exportedAt, clock.now());
      expect(restored.profile?['fullName'], 'Anita Rao');
      expect(restored.subjects, contains('Mathematics'));
      expect(restored.periods, hasLength(2));
      expect(restored.entries.single.room, 'R-12');
      expect(restored.sessions.single.note, 'Finished chapter 4');
      expect(restored.events.single.title, 'Unit test 2');
      expect(restored.overrides.single.slots.single.isInvigilating, isTrue);
    });

    test('an empty device still produces a valid file', () {
      final BackupPayload restored =
          BackupPayload.decode(backup.snapshot().encode());

      expect(restored.entries, isEmpty);
      // Subjects fall back to the defaults, so the file is never truly empty.
      expect(restored.subjects, isNotEmpty);
    });

    test('the filename is dated so several can be told apart', () {
      expect(backup.suggestedFileName(), 'teachtrack-backup-2026-07-30.json');
    });

    test('the summary describes what is inside', () async {
      await seedEverything();

      expect(backup.snapshot().contentsSummary, contains('1 classes'));
      expect(backup.snapshot().contentsSummary, contains('1 events'));
    });
  });

  group('payload rejection', () {
    test('refuses a file that is not JSON', () {
      expect(
        () => BackupPayload.decode('not json at all'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('refuses JSON that is not one of ours', () {
      expect(
        () => BackupPayload.decode('{"hello":"world"}'),
        throwsA(
          isA<BackupFormatException>().having(
            (BackupFormatException e) => e.message,
            'message',
            contains('not a TeachTrack backup'),
          ),
        ),
      );
    });

    test('refuses a backup from a newer version of the app', () {
      final String source = jsonEncode(<String, dynamic>{
        'format': BackupPayload.formatMarker,
        'version': BackupPayload.currentVersion + 1,
        'exportedAt': DateTime(2026, 7, 30).toIso8601String(),
      });

      expect(
        () => BackupPayload.decode(source),
        throwsA(
          isA<BackupFormatException>().having(
            (BackupFormatException e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('refuses a backup with no export date', () {
      final String source = jsonEncode(<String, dynamic>{
        'format': BackupPayload.formatMarker,
        'version': 1,
      });

      expect(
        () => BackupPayload.decode(source),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('skips one unparseable record rather than losing the file', () {
      final String source = jsonEncode(<String, dynamic>{
        'format': BackupPayload.formatMarker,
        'version': 1,
        'exportedAt': DateTime(2026, 7, 30).toIso8601String(),
        'entries': <dynamic>[
          entry.toJson(),
          <String, dynamic>{'nonsense': true},
          'not even a map',
        ],
      });

      final BackupPayload payload = BackupPayload.decode(source);

      expect(
        payload.entries,
        hasLength(1),
        reason: 'losing one class beats losing two hundred',
      );
    });
  });

  group('restore', () {
    test('a full round trip puts everything back on an empty device', () async {
      await seedEverything();
      final BackupPayload file = backup.snapshot();

      // Wipe, as a new phone would be.
      await timetable.clearAllData();
      await overrideLocal.delete('ov1');
      await eventLocal.delete('ev1');
      await settings.delete(SettingsKeys.teacherProfile);
      expect(timetableLocal.allEntries(), isEmpty);

      final result = await backup.restore(file, mode: RestoreMode.replace);
      final RestoreSummary summary = result.valueOrNull!;

      expect(summary.entries, 1);
      expect(summary.sessions, 1);
      expect(summary.events, 1);
      expect(summary.overrides, 1);
      expect(summary.periods, 2);
      expect(summary.profileRestored, isTrue);
      expect(summary.skipped, 0);

      expect(timetableLocal.entryById('e1')?.subject, 'Mathematics');
      expect(overrideLocal.byId('ov1')?.slots, hasLength(1));
      expect(eventLocal.byId('ev1')?.title, 'Unit test 2');
      expect(
        timetableLocal.sessionById(ClassSession.buildId(thursday, 'e1'))?.note,
        'Finished chapter 4',
      );
    });

    test('restoring marks setup complete, so the wizard does not reappear',
        () async {
      await seedEverything();
      final BackupPayload file = backup.snapshot();
      await settings.delete(SettingsKeys.onboardingCompleted);

      await backup.restore(file, mode: RestoreMode.replace);

      expect(settings.get(SettingsKeys.onboardingCompleted), isTrue);
    });

    test('replace clears what was there first, leaving no duplicates', () async {
      await seedEverything();
      final BackupPayload file = backup.snapshot();

      // Restore onto a device that already holds the same data.
      final result = await backup.restore(file, mode: RestoreMode.replace);

      expect(result.isOk, isTrue);
      expect(timetableLocal.allEntries(), hasLength(1));
      expect(eventLocal.all(), hasLength(1));
      expect(overrideLocal.all(), hasLength(1));
    });

    test('merge keeps what is already there and skips the incoming copy',
        () async {
      await seedEverything();
      final BackupPayload file = backup.snapshot();

      final result = await backup.restore(file, mode: RestoreMode.merge);
      final RestoreSummary summary = result.valueOrNull!;

      expect(
        summary.entries,
        0,
        reason: 'the entry already exists, so it is left alone',
      );
      expect(timetableLocal.allEntries(), hasLength(1));
    });

    test('merge adds a record the device does not have', () async {
      await seedEverything();
      final BackupPayload file = backup.snapshot();
      await timetableLocal.deleteEntry('e1');

      final result = await backup.restore(file, mode: RestoreMode.merge);

      expect(result.valueOrNull!.entries, 1);
      expect(timetableLocal.entryById('e1'), isNotNull);
    });

    test('merge skips a class whose slot is already taken', () async {
      await seedEverything();
      final BackupPayload file = backup.snapshot();

      // A different class now occupies the same weekday and period.
      await timetableLocal.deleteEntry('e1');
      await timetableLocal.putEntry(
        const TimetableEntry(
          id: 'other',
          weekday: DateTime.thursday,
          periodId: 'p1',
          subject: 'Science',
          classGroup: '9A',
        ),
      );

      final result = await backup.restore(file, mode: RestoreMode.merge);

      expect(
        result.valueOrNull!.skipped,
        greaterThan(0),
        reason: 'two classes in one period must never both be stored',
      );
      expect(timetableLocal.entryById('e1'), isNull);
      expect(timetableLocal.entryById('other')?.subject, 'Science');
    });

    test('an empty payload is refused rather than wiping the device', () async {
      await seedEverything();

      final result = await backup.restore(
        BackupPayload(exportedAt: clock.now()),
        mode: RestoreMode.replace,
      );

      expect(result.isErr, isTrue);
      expect(
        timetableLocal.allEntries(),
        hasLength(1),
        reason: 'a corrupt or empty file must not cost the teacher their data',
      );
    });

    test('a restore queues work for the outbox', () async {
      await seedEverything();
      final BackupPayload file = backup.snapshot();
      await timetable.clearAllData();

      await backup.restore(file, mode: RestoreMode.replace);

      expect(
        queue.pendingCount,
        greaterThan(0),
        reason: 'restored data must reach the cloud once one exists',
      );
    });
  });
}
