import '../../../shared/models/pending_operation.dart';

/// Contract every feature implements to push its queued writes upstream.
///
/// The sync engine knows nothing about Firestore. Each feature registers a
/// handler for its own entity type, which keeps `core` free of backend
/// dependencies and lets modules be added without touching the engine.
abstract interface class RemoteSyncHandler {
  /// Routing key — must match the `entityType` used when enqueuing.
  String get entityType;

  /// Pushes [operations] upstream as a single unit.
  ///
  /// Implementations should use a Firestore `WriteBatch` so that N local edits
  /// cost one round trip. Throwing marks the whole batch for retry, so
  /// implementations must be idempotent: a batch may be applied twice if the
  /// response is lost after the server commits.
  Future<void> applyBatch(List<PendingOperation> operations);
}

/// Default handler used until a real backend is wired up.
///
/// It deliberately does nothing and reports success, so the queue drains and
/// the full offline pipeline can be exercised end to end without Firebase.
class NoopSyncHandler implements RemoteSyncHandler {
  const NoopSyncHandler(this.entityType);

  @override
  final String entityType;

  @override
  Future<void> applyBatch(List<PendingOperation> operations) async {}
}
