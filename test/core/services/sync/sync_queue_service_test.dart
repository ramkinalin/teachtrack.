import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/app_constants.dart';
import 'package:teachtrack/core/constants/hive_boxes.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';

void main() {
  late Directory tempDir;
  late Box<PendingOperation> box;
  late FakeClock clock;
  late SyncQueueService queue;

  // Local (not UTC): Hive round-trips DateTime through epoch millis and returns
  // a local instant, and DateTime equality also compares the isUtc flag.
  final DateTime start = DateTime(2026, 7, 29, 9);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_queue_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }

    box = await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations);
    clock = FakeClock(start);
    queue = SyncQueueService(box: box, clock: clock);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('enqueue', () {
    test('appends a new operation', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a1',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{'present': true},
      );

      expect(queue.pendingCount, 1);
      expect(queue.dueOperations().single.entityId, 'a1');
    });

    test('coalesces repeated updates into one operation, merging payloads',
        () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.classSession,
        entityId: 'c1',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'completed': false, 'note': 'first'},
      );
      await queue.enqueue(
        entityType: SyncEntityTypes.classSession,
        entityId: 'c1',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'completed': true},
      );

      expect(queue.pendingCount, 1, reason: 'one remote write, not two');
      final PendingOperation op = queue.dueOperations().single;
      expect(op.payload['completed'], true);
      expect(op.payload['note'], 'first', reason: 'earlier fields survive');
    });

    test('keeps create semantics when a create is followed by an update',
        () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentItem,
        entityId: 'e1',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{'name': 'Cones'},
      );
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentItem,
        entityId: 'e1',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'quantity': 20},
      );

      final PendingOperation op = queue.dueOperations().single;
      expect(op.operation, SyncOperationType.create);
      expect(op.payload['quantity'], 20);
    });

    test('drops the operation entirely when a create is then deleted',
        () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentItem,
        entityId: 'e2',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{'name': 'Temp'},
      );
      final PendingOperation? result = await queue.enqueue(
        entityType: SyncEntityTypes.equipmentItem,
        entityId: 'e2',
        operation: SyncOperationType.delete,
        payload: <String, dynamic>{},
      );

      expect(result, isNull);
      expect(queue.pendingCount, 0, reason: 'never reached the server');
    });

    test('converts a pending update into a delete', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentCheckout,
        entityId: 'k1',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'returned': false},
      );
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentCheckout,
        entityId: 'k1',
        operation: SyncOperationType.delete,
        payload: <String, dynamic>{},
      );

      expect(queue.pendingCount, 1);
      expect(queue.dueOperations().single.operation, SyncOperationType.delete);
    });

    test('a re-create after a queued delete replaces the delete', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentItem,
        entityId: 'e3',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'quantity': 5},
      );
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentItem,
        entityId: 'e3',
        operation: SyncOperationType.delete,
        payload: <String, dynamic>{},
      );
      await queue.enqueue(
        entityType: SyncEntityTypes.equipmentItem,
        entityId: 'e3',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{'name': 'Cones'},
      );

      expect(queue.pendingCount, 1);
      final PendingOperation op = queue.dueOperations().single;
      expect(op.operation, SyncOperationType.create);
      expect(op.payload['name'], 'Cones');
      expect(
        op.payload.containsKey('quantity'),
        isFalse,
        reason: 'fields from the deleted record must not be resurrected',
      );
    });

    test('does not coalesce into an operation that is in flight', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.classSession,
        entityId: 'c1',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'completed': false},
      );

      final List<PendingOperation> dispatched = queue.dueOperations();
      queue.markDispatching(dispatched);

      expect(queue.dueOperations(), isEmpty, reason: 'no double dispatch');

      await queue.enqueue(
        entityType: SyncEntityTypes.classSession,
        entityId: 'c1',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'completed': true},
      );

      expect(queue.pendingCount, 2, reason: 'a separate entry was created');

      await queue.markSucceeded(dispatched);

      final PendingOperation remaining = queue.dueOperations().single;
      expect(remaining.payload['completed'], true);
    });

    test('does not coalesce across different entities', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a1',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{},
      );
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a2',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{},
      );

      expect(queue.pendingCount, 2);
    });
  });

  group('retry scheduling', () {
    test('back-off grows exponentially and is capped', () {
      expect(
        SyncQueueService.backoffFor(1),
        AppConstants.syncRetryBaseDelay,
      );
      expect(
        SyncQueueService.backoffFor(2),
        AppConstants.syncRetryBaseDelay * 2,
      );
      expect(
        SyncQueueService.backoffFor(4),
        AppConstants.syncRetryBaseDelay * 8,
      );
      expect(
        SyncQueueService.backoffFor(50),
        AppConstants.syncRetryMaxDelay,
        reason: 'must never exceed the cap or overflow',
      );
    });

    test('a failed operation is not due until its back-off elapses', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a1',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{},
      );

      await queue.markFailed(queue.dueOperations(), 'network down');

      expect(queue.dueOperations(), isEmpty);
      expect(queue.pendingCount, 1, reason: 'still queued, just not yet due');

      clock.advance(AppConstants.syncRetryBaseDelay);
      expect(queue.dueOperations(), hasLength(1));
    });

    test('dead-letters after the attempt budget is exhausted', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a1',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{},
      );

      for (int i = 0; i < AppConstants.syncMaxAttempts; i++) {
        final List<PendingOperation> due = queue.dueOperations();
        if (due.isEmpty) break;
        await queue.markFailed(due, 'still failing');
        clock.advance(AppConstants.syncRetryMaxDelay);
      }

      expect(queue.deadLetteredCount, 1);
      expect(queue.pendingCount, 0);
      expect(queue.dueOperations(), isEmpty, reason: 'stops burning quota');
    });

    test('requeue clears the dead-letter flag and back-off', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a1',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{},
      );

      for (int i = 0; i < AppConstants.syncMaxAttempts; i++) {
        final List<PendingOperation> due = queue.dueOperations();
        if (due.isEmpty) break;
        await queue.markFailed(due, 'still failing');
        clock.advance(AppConstants.syncRetryMaxDelay);
      }

      await queue.requeue(queue.deadLetteredOperations().single);

      expect(queue.deadLetteredCount, 0);
      expect(queue.dueOperations(), hasLength(1));
      expect(queue.dueOperations().single.attemptCount, 0);
    });

    test('earliestScheduledAttempt reports the soonest retry', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a1',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{},
      );
      await queue.markFailed(queue.dueOperations(), 'boom');

      expect(
        queue.earliestScheduledAttempt(),
        start.add(AppConstants.syncRetryBaseDelay),
      );
    });
  });

  group('markSucceeded', () {
    test('removes operations from the outbox', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.attendance,
        entityId: 'a1',
        operation: SyncOperationType.create,
        payload: <String, dynamic>{},
      );

      await queue.markSucceeded(queue.dueOperations());

      expect(queue.pendingCount, 0);
      expect(box.isEmpty, isTrue);
    });
  });

  group('durability', () {
    test('operations survive a box reopen', () async {
      await queue.enqueue(
        entityType: SyncEntityTypes.classSession,
        entityId: 'c9',
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'completed': true, 'count': 3},
      );

      await box.close();
      final Box<PendingOperation> reopened =
          await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations);
      final SyncQueueService reloaded =
          SyncQueueService(box: reopened, clock: clock);

      final PendingOperation op = reloaded.dueOperations().single;
      expect(op.entityId, 'c9');
      expect(op.operation, SyncOperationType.update);
      expect(op.payload['completed'], true);
      expect(op.payload['count'], 3);
      expect(op.createdAt, start);
    });
  });
}
