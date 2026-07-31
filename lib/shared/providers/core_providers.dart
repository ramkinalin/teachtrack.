import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/sync/remote_sync_handler.dart';
import '../../core/services/sync/sync_engine.dart';
import '../../core/services/sync/sync_queue_service.dart';
import '../../core/utils/clock.dart';

/// Injectable time source — override in tests with [FakeClock].
final Provider<Clock> clockProvider = Provider<Clock>((ref) => const Clock());

/// Overridden in `main()` with the instance whose `init()` has been awaited.
///
/// Deliberately throws by default: reaching a box before initialisation is a
/// programming error, not something to paper over with lazy async access.
final Provider<LocalStorageService> localStorageServiceProvider =
    Provider<LocalStorageService>(
  (ref) => throw UnimplementedError(
    'localStorageServiceProvider must be overridden in main() with an '
    'initialised LocalStorageService.',
  ),
);

final Provider<ConnectivityService> connectivityServiceProvider =
    Provider<ConnectivityService>((ref) {
  final ConnectivityService service = ConnectivityPlusService();
  ref.onDispose(service.dispose);
  return service;
});

final StreamProvider<bool> isOnlineProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).onStatusChanged;
});

final Provider<SyncQueueService> syncQueueServiceProvider =
    Provider<SyncQueueService>((ref) {
  return SyncQueueService(
    box: ref.watch(localStorageServiceProvider).pendingOperationsBox,
    clock: ref.watch(clockProvider),
  );
});

/// Handlers each feature registers for its own entity type.
///
/// Features override this provider by appending their handler, which keeps the
/// engine unaware of any concrete backend. Until Firebase is wired up, no-op
/// handlers let the whole pipeline run end to end.
final Provider<List<RemoteSyncHandler>> remoteSyncHandlersProvider =
    Provider<List<RemoteSyncHandler>>(
  // Every entity type a repository can enqueue must appear here, or the engine
  // finds no handler, retries eight times and dead-letters the write.
  (ref) => const <RemoteSyncHandler>[
    NoopSyncHandler(SyncEntityTypes.classSession),
    NoopSyncHandler(SyncEntityTypes.timetableEntry),
    NoopSyncHandler(SyncEntityTypes.period),
    NoopSyncHandler(SyncEntityTypes.teacherProfile),
    NoopSyncHandler(SyncEntityTypes.schoolEvent),
    NoopSyncHandler(SyncEntityTypes.attendance),
    NoopSyncHandler(SyncEntityTypes.equipmentCheckout),
    NoopSyncHandler(SyncEntityTypes.equipmentItem),
  ],
);

final Provider<SyncEngine> syncEngineProvider = Provider<SyncEngine>((ref) {
  final SyncEngine engine = SyncEngine(
    queue: ref.watch(syncQueueServiceProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    storage: ref.watch(localStorageServiceProvider),
    clock: ref.watch(clockProvider),
  );

  for (final RemoteSyncHandler handler
      in ref.watch(remoteSyncHandlersProvider)) {
    engine.registerHandler(handler);
  }

  ref.onDispose(engine.dispose);
  return engine;
});
