import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/hive_boxes.dart';
import 'package:teachtrack/core/services/notifications/notification_service.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/features/events/data/local/event_local_data_source.dart';
import 'package:teachtrack/features/events/data/repositories/event_repository_impl.dart';
import 'package:teachtrack/features/events/domain/entities/school_event.dart';
import 'package:teachtrack/features/events/domain/event_reminder_coordinator.dart';
import 'package:teachtrack/features/events/domain/event_reminder_planner.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';

void main() {
  late Directory tempDir;
  late EventLocalDataSource local;
  late EventRepositoryImpl repository;
  late FakeNotificationService notifications;
  late EventReminderCoordinator coordinator;
  late FakeClock clock;

  final DateTime thursday = DateTime(2026, 7, 30);

  SchoolEvent event({
    String id = 'ev1',
    DateTime? date,
    int? startMinute = 600,
    List<int> reminders = const <int>[60],
  }) =>
      SchoolEvent(
        id: id,
        date: date ?? thursday,
        category: SchoolEventCategory.classTest,
        title: 'Unit test',
        startMinute: startMinute,
        reminderLeadMinutes: reminders,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_reminders');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }

    local = EventLocalDataSource();
    await local.init();

    // 08:00 on the Thursday, so a 60-minute lead on a 10:00 event is still ahead.
    clock = FakeClock(DateTime(2026, 7, 30, 8));
    repository = EventRepositoryImpl(
      local: local,
      syncQueue: SyncQueueService(
        box: await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations),
        clock: clock,
      ),
      clock: clock,
    );
    notifications = FakeNotificationService();
    coordinator = EventReminderCoordinator(
      repository: repository,
      notifications: notifications,
      clock: clock,
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('schedules a reminder for an upcoming event', () async {
    await repository.upsert(event());

    final int? count = await coordinator.sync();

    expect(count, 1);
    expect(notifications.scheduled, hasLength(1));
    expect(
      notifications.scheduled.values.single.payload,
      EventReminderPlanner.payloadFor('ev1', 60),
    );
  });

  test('initialises the plugin before scheduling', () async {
    await coordinator.sync();

    expect(notifications.initCalls, greaterThan(0));
  });

  test('does not request permission unless asked', () async {
    await coordinator.sync();
    expect(notifications.permissionRequests, 0);

    await coordinator.sync(requestPermission: true);
    expect(notifications.permissionRequests, 1);
  });

  test('schedules nothing when permission is refused', () async {
    await repository.upsert(event());
    notifications.permissionGranted = false;

    final int? count = await coordinator.sync(requestPermission: true);

    expect(count, isNull, reason: 'null tells the caller to explain why');
    expect(notifications.scheduled, isEmpty);
  });

  test('a second sync replaces rather than duplicates', () async {
    await repository.upsert(event());

    await coordinator.sync();
    await coordinator.sync();

    expect(
      notifications.scheduled,
      hasLength(1),
      reason: 'ids are derived, so rescheduling overwrites',
    );
    expect(notifications.cancelled, isNotEmpty);
  });

  test('reminders for a deleted event are dropped on the next sync', () async {
    await repository.upsert(event());
    await coordinator.sync();
    expect(notifications.scheduled, hasLength(1));

    await repository.delete('ev1');
    await coordinator.sync();

    expect(notifications.scheduled, isEmpty);
  });

  test('removing the reminders from an event clears its notification', () async {
    await repository.upsert(event());
    await coordinator.sync();

    await repository.upsert(event(reminders: const <int>[]));
    await coordinator.sync();

    expect(notifications.scheduled, isEmpty);
  });

  test('an all-day event added after 08:00 schedules nothing today', () async {
    // The trap that made a real reminder silently fail: with no time, leads are
    // counted back from 08:00, so anything added during the day is already past.
    // Correct behaviour, but the form now says so rather than staying quiet.
    await repository.upsert(
      event(startMinute: null, reminders: const <int>[60]),
    );

    expect(await coordinator.sync(), 0);
    expect(notifications.scheduled, isEmpty);
  });

  test('past events contribute nothing', () async {
    await repository.upsert(event(date: DateTime(2026, 7, 1)));

    expect(await coordinator.sync(), 0);
    expect(notifications.scheduled, isEmpty);
  });

  test('only future reminders of a part-elapsed event are scheduled', () async {
    // 10:00 event with day-before and hour-before leads; standing at 08:00 the
    // first has passed and the second has not.
    await repository.upsert(event(reminders: const <int>[1440, 60]));

    expect(await coordinator.sync(), 1);
  });

  test('cancelAll drops only this app\'s reminders', () async {
    await repository.upsert(event());
    await coordinator.sync();

    // A notification belonging to something else entirely.
    await notifications.schedule(
      id: 99,
      when: DateTime(2026, 8, 1),
      title: 'Other app',
      body: 'Not ours',
      payload: 'somethingelse:1',
    );

    await coordinator.cancelAll();

    expect(notifications.scheduled.keys, <int>[99]);
  });

  test('overlapping syncs queue rather than reporting a permission problem',
      () async {
    await repository.upsert(event());

    // An earlier version returned null when a sync was already running, which
    // callers could not tell apart from a refused permission.
    final List<int?> results = await Future.wait<int?>(<Future<int?>>[
      coordinator.sync(),
      coordinator.sync(),
      coordinator.sync(),
    ]);

    expect(results, everyElement(isNotNull));
    expect(results, everyElement(1));
    expect(notifications.scheduled, hasLength(1));
  });

  test('several events each get their own reminders', () async {
    await repository.upsert(event(id: 'a', date: DateTime(2026, 8, 1)));
    await repository.upsert(event(id: 'b', date: DateTime(2026, 8, 2)));

    expect(await coordinator.sync(), 2);
    expect(
      notifications.scheduled.values
          .map((PendingNotificationRequest r) => r.payload)
          .toSet(),
      <String>{
        EventReminderPlanner.payloadFor('a', 60),
        EventReminderPlanner.payloadFor('b', 60),
      },
    );
  });
}
