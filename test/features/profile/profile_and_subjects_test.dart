import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/app_constants.dart';
import 'package:teachtrack/core/constants/hive_boxes.dart';
import 'package:teachtrack/core/errors/failures.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/features/profile/data/profile_repository_impl.dart';
import 'package:teachtrack/features/profile/domain/teacher_profile.dart';
import 'package:teachtrack/features/timetable/data/local/subject_store.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> settings;
  late SyncQueueService queue;
  late ProfileRepositoryImpl profiles;
  late SubjectStore subjects;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_profile');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }

    settings = await Hive.openBox<dynamic>(HiveBoxes.settings);
    queue = SyncQueueService(
      box: await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations),
      clock: FakeClock(DateTime(2026, 7, 30, 9)),
    );
    profiles = ProfileRepositoryImpl(settingsBox: settings, syncQueue: queue);
    subjects = SubjectStore(settingsBox: settings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('ProfileRepository', () {
    test('starts with no profile and setup incomplete', () {
      expect(profiles.profile(), isNull);
      expect(profiles.isOnboardingCompleted, isFalse);
    });

    test('saves a profile and queues it for sync', () async {
      final result = await profiles.saveProfile(
        fullName: '  N. Ramakrishnan  ',
        schoolName: 'Kendriya Vidyalaya',
        classTeacherOf: '8B',
      );

      final TeacherProfile saved = result.valueOrNull!;
      expect(saved.fullName, 'N. Ramakrishnan', reason: 'trimmed');
      expect(saved.isClassTeacher, isTrue);
      expect(saved.displaySubtitle, 'Class teacher of 8B');

      final PendingOperation op = queue.dueOperations().single;
      expect(op.entityType, SyncEntityTypes.teacherProfile);
      expect(op.entityId, saved.id);
    });

    test('rejects a blank name', () async {
      final result = await profiles.saveProfile(fullName: '   ');

      expect(result.isErr, isTrue);
      expect(
        (result.failureOrNull! as ValidationFailure).field,
        'fullName',
      );
      expect(profiles.profile(), isNull);
    });

    test('keeps the same id across edits', () async {
      final String first =
          (await profiles.saveProfile(fullName: 'First')).valueOrNull!.id;
      final String second =
          (await profiles.saveProfile(fullName: 'Second')).valueOrNull!.id;

      expect(
        second,
        first,
        reason: 'the id is already stamped on existing timetable entries',
      );
    });

    test('a profile survives a reload', () async {
      await profiles.saveProfile(fullName: 'Anita Rao', staffId: 'T-4471');

      final ProfileRepositoryImpl reloaded = ProfileRepositoryImpl(
        settingsBox: settings,
        syncQueue: queue,
      );

      expect(reloaded.profile()?.fullName, 'Anita Rao');
      expect(reloaded.profile()?.staffId, 'T-4471');
    });

    test('corrupt stored data degrades to no profile rather than crashing',
        () async {
      await settings.put(SettingsKeys.teacherProfile, 'not json at all');

      expect(profiles.profile(), isNull);
    });

    test('clearing the class-teacher section drops the flag', () async {
      await profiles.saveProfile(fullName: 'Anita', classTeacherOf: '8B');
      await profiles.saveProfile(fullName: 'Anita');

      expect(profiles.profile()?.isClassTeacher, isFalse);
      expect(profiles.profile()?.displaySubtitle, 'Subject teacher');
    });

    test('reset clears the profile and the setup flag', () async {
      await profiles.saveProfile(fullName: 'Anita');
      await profiles.setOnboardingCompleted(value: true);

      await profiles.reset();

      expect(profiles.profile(), isNull);
      expect(profiles.isOnboardingCompleted, isFalse);
    });
  });

  group('SubjectStore', () {
    test('offers the defaults before anything is stored', () {
      expect(subjects.subjects(), containsAll(<String>['Mathematics', 'Hindi']));
    });

    test('seeding persists the defaults so a later edit keeps them', () async {
      await subjects.seedIfEmpty();
      await subjects.add('Sanskrit');

      expect(subjects.subjects(), contains('Mathematics'));
      expect(subjects.subjects(), contains('Sanskrit'));
    });

    test('seeding twice does not duplicate or reset', () async {
      await subjects.seedIfEmpty();
      await subjects.remove('Mathematics');
      await subjects.seedIfEmpty();

      expect(subjects.subjects(), isNot(contains('Mathematics')));
    });

    test('a case-variant returns the existing spelling instead of duplicating',
        () async {
      await subjects.seedIfEmpty();

      final String? canonical = await subjects.add('mathematics');

      expect(canonical, 'Mathematics');
      expect(
        subjects.subjects().where((String s) => s.toLowerCase() == 'mathematics'),
        hasLength(1),
      );
    });

    test('blank names are refused', () async {
      expect(await subjects.add('   '), isNull);
    });

    test('names are trimmed on the way in', () async {
      await subjects.seedIfEmpty();

      expect(await subjects.add('  Sanskrit  '), 'Sanskrit');
      expect(subjects.subjects(), contains('Sanskrit'));
    });

    test('remove is case-insensitive', () async {
      await subjects.seedIfEmpty();

      expect(await subjects.remove('mathematics'), isTrue);
      expect(subjects.subjects(), isNot(contains('Mathematics')));
    });

    test('removing something not in the list is refused', () async {
      await subjects.seedIfEmpty();

      expect(await subjects.remove('Astrophysics'), isFalse);
    });

    test('the list is returned in case-insensitive alphabetical order',
        () async {
      await subjects.seedIfEmpty();
      await subjects.add('aardvark studies');

      expect(subjects.subjects().first, 'aardvark studies');
    });

    test('the last subject cannot be removed', () async {
      await subjects.seedIfEmpty();
      for (final String subject in subjects.subjects().toList()) {
        await subjects.remove(subject);
      }

      final List<String> remaining = subjects.subjects();

      expect(
        remaining,
        hasLength(1),
        reason: 'a dropdown with no options would be a dead end, and an empty '
            'stored list would resurrect all the defaults',
      );
    });

    test('restoreDefaults discards additions', () async {
      await subjects.seedIfEmpty();
      await subjects.add('Sanskrit');

      await subjects.restoreDefaults();

      expect(subjects.subjects(), isNot(contains('Sanskrit')));
      expect(subjects.subjects(), contains('Mathematics'));
    });
  });
}
