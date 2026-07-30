import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:teachtrack/core/constants/app_constants.dart';
import 'package:teachtrack/core/services/connectivity_service.dart';
import 'package:teachtrack/core/services/local_storage_service.dart';
import 'package:teachtrack/core/services/sync/remote_sync_handler.dart';
import 'package:teachtrack/core/services/sync/sync_engine.dart';
import 'package:teachtrack/core/services/sync/sync_queue_service.dart';
import 'package:teachtrack/core/utils/clock.dart';
import 'package:teachtrack/shared/models/pending_operation.dart';
import 'package:teachtrack/shared/models/sync_state.dart';

/// Records the batches it receives and can be told to fail.
class RecordingHandler implements RemoteSyncHandler {
  RecordingHandler(this.entityType);

  @override
  final String entityType;

  final List<List<PendingOperation>> batches = <List<PendingOperation>>[];
  bool shouldFail = false;

  /// When set, the handler blocks until this future completes, simulating a slow
  /// remote call so behaviour during an in-flight batch can be tested.
  Future<void>? gate;

  @override
  Future<void> applyBatch(List<PendingOperation> operations) async {
    batches.add(operations);
    final Future<void>? pending = gate;
    if (pending != null) await pending;
    if (shouldFail) throw StateError('remote unavailable');
  }
}

void main() {
  late Directory tempDir;
  late LocalStorageService storage;
  late FakeClock clock;
  late FakeConnectivityService connectivity;
  late SyncQueueService queue;
  late SyncEngine engine;
  late RecordingHandler sessions;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('teachtrack_engine_test');
    Hive.init(tempDir.path);

    storage = LocalStorageService();
    await storage.init(useFlutterPath: false);

    clock = FakeClock(DateTime(2026, 7, 29, 9));
    connectivity = FakeConnectivityService(initialOnline: true);
    queue = SyncQueueService(box: storage.pendingOperationsBox, clock: clock);
    sessions = RecordingHandler(SyncEntityTypes.classSession);

    engine = SyncEngine(
      queue: queue,
      connectivity: connectivity,
      storage: storage,
      clock: clock,
    )..registerHandler(sessions);
  });

  tearDown(() async {
    await engine.dispose();
    await connectivity.dispose();
    await Hive.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> enqueue(String entityId, {String? entityType}) => queue.enqueue(
        entityType: entityType ?? SyncEntityTypes.classSession,
        entityId: entityId,
        operation: SyncOperationType.update,
        payload: <String, dynamic>{'completed': true},
      );

  test('drains the outbox and clears it on success', () async {
    await enqueue('c1');
    await engine.start();

    expect(sessions.batches, hasLength(1));
    expect(queue.pendingCount, 0);
    expect(engine.state.status, SyncStatus.synced);
    expect(storage.lastSuccessfulSyncAt, clock.now());
  });

  test('sends one batch per entity type, not one call per operation', () async {
    await enqueue('c1');
    await enqueue('c2');
    await enqueue('c3');

    await engine.start();

    expect(sessions.batches, hasLength(1));
    expect(sessions.batches.single, hasLength(3));
  });

  test('does nothing while offline and keeps writes queued', () async {
    connectivity.setOnline(false);
    await enqueue('c1');
    await engine.start();

    expect(sessions.batches, isEmpty);
    expect(queue.pendingCount, 1);
    expect(engine.state.status, SyncStatus.offline);
  });

  test('drains automatically when connectivity returns', () async {
    connectivity.setOnline(false);
    await enqueue('c1');
    await engine.start();
    expect(sessions.batches, isEmpty);

    connectivity.setOnline(true);
    await Future<void>.delayed(Duration.zero);
    await engine.drain();

    expect(sessions.batches, hasLength(1));
    expect(queue.pendingCount, 0);
  });

  test('a failed batch stays queued and is retried after the back-off',
      () async {
    sessions.shouldFail = true;
    await enqueue('c1');
    await engine.start();

    expect(queue.pendingCount, 1);
    expect(engine.state.status, SyncStatus.retrying);
    expect(engine.state.lastError, isNotNull);

    // Not yet due — a second pass must not hammer the backend.
    await engine.drain();
    expect(sessions.batches, hasLength(1));

    sessions.shouldFail = false;
    clock.advance(AppConstants.syncRetryBaseDelay);
    await engine.drain();

    expect(sessions.batches, hasLength(2));
    expect(queue.pendingCount, 0);
    expect(engine.state.status, SyncStatus.synced);
  });

  test('operations with no registered handler are dead-lettered, not lost',
      () async {
    await enqueue('x1', entityType: SyncEntityTypes.equipmentItem);
    await engine.start();

    expect(sessions.batches, isEmpty);
    expect(queue.pendingCount, 1, reason: 'retained for retry');

    for (int i = 0; i < AppConstants.syncMaxAttempts; i++) {
      clock.advance(AppConstants.syncRetryMaxDelay);
      await engine.drain();
    }

    expect(queue.deadLetteredCount, 1);
    expect(engine.state.status, SyncStatus.needsAttention);
  });

  test('an edit made during an in-flight batch is not swallowed', () async {
    await engine.start();

    final Completer<void> remoteCall = Completer<void>();
    sessions.gate = remoteCall.future;
    await enqueue('c1');

    final Future<void> pass = engine.drain();
    await Future<void>.delayed(Duration.zero);
    expect(sessions.batches, hasLength(1), reason: 'batch is in flight');

    // Teacher edits the same class again before the batch completes. This must
    // not coalesce into the in-flight operation, which is about to be deleted.
    await queue.enqueue(
      entityType: SyncEntityTypes.classSession,
      entityId: 'c1',
      operation: SyncOperationType.update,
      payload: <String, dynamic>{'note': 'later edit'},
    );

    sessions.gate = null;
    remoteCall.complete();
    await pass;

    expect(queue.pendingCount, 1, reason: 'the later edit survived');

    await engine.drain();
    expect(sessions.batches, hasLength(2));
    expect(sessions.batches.last.single.payload['note'], 'later edit');
    expect(queue.pendingCount, 0);
  });

  test('concurrent drain calls collapse into a single pass', () async {
    await enqueue('c1');
    await engine.start();
    await enqueue('c2');

    await Future.wait<void>(<Future<void>>[
      engine.drain(),
      engine.drain(),
      engine.drain(),
    ]);

    // One batch from start(), one from the collapsed concurrent calls.
    expect(sessions.batches, hasLength(2));
    expect(queue.pendingCount, 0);
  });
}
