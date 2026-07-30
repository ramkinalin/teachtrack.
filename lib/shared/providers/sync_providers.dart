import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/sync/sync_engine.dart';
import '../models/pending_operation.dart';
import '../models/sync_state.dart';
import 'core_providers.dart';

/// Starts the engine and exposes its state.
///
/// Not auto-disposed, so background synchronisation keeps running for the whole
/// session even when no widget is currently observing it.
final StreamProvider<SyncState> syncStateProvider =
    StreamProvider<SyncState>((ref) {
  final SyncEngine engine = ref.watch(syncEngineProvider);
  // Fire-and-forget: startup must never block the first frame.
  Future<void>.microtask(engine.start);
  return engine.states;
});

/// Convenience selectors for badges and banners.
final Provider<int> pendingSyncCountProvider = Provider<int>((ref) {
  return ref.watch(syncStateProvider).maybeWhen(
        data: (SyncState state) => state.pendingCount,
        orElse: () => 0,
      );
});

final Provider<SyncStatus> syncStatusProvider = Provider<SyncStatus>((ref) {
  return ref.watch(syncStateProvider).maybeWhen(
        data: (SyncState state) => state.status,
        orElse: () => SyncStatus.offline,
      );
});

/// Emits whenever the outbox itself changes, so views over queue contents stay
/// live rather than refreshing only when the engine happens to report state.
final outboxChangesProvider = StreamProvider.autoDispose<void>((ref) {
  return ref.watch(syncQueueServiceProvider).watchChanges();
});

/// Operations that exhausted their retries and need a decision from the user.
final deadLetteredOperationsProvider =
    Provider.autoDispose<List<PendingOperation>>((ref) {
  ref.watch(outboxChangesProvider);
  return ref.watch(syncQueueServiceProvider).deadLetteredOperations();
});
