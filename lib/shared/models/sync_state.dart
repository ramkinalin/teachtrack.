/// High-level synchronisation status shown in the UI.
enum SyncStatus {
  /// Online, outbox empty.
  synced,

  /// A drain pass is in flight.
  syncing,

  /// No connection; writes are accumulating locally. Not an error state.
  offline,

  /// Last attempt failed; a retry is scheduled.
  retrying,

  /// One or more operations exhausted their retries and need attention.
  needsAttention,
}

/// Immutable snapshot of the sync subsystem, exposed to the presentation layer.
class SyncState {
  const SyncState({
    this.status = SyncStatus.offline,
    this.pendingCount = 0,
    this.deadLetteredCount = 0,
    this.lastSuccessfulSyncAt,
    this.lastError,
  });

  final SyncStatus status;
  final int pendingCount;
  final int deadLetteredCount;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastError;

  bool get hasUnsyncedWork => pendingCount > 0;

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    int? deadLetteredCount,
    DateTime? lastSuccessfulSyncAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      deadLetteredCount: deadLetteredCount ?? this.deadLetteredCount,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  // Value equality matters here: the engine re-emits on every Hive box event,
  // and without it every consumer would rebuild on identical state.
  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.status == status &&
      other.pendingCount == pendingCount &&
      other.deadLetteredCount == deadLetteredCount &&
      other.lastSuccessfulSyncAt == lastSuccessfulSyncAt &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(
        status,
        pendingCount,
        deadLetteredCount,
        lastSuccessfulSyncAt,
        lastError,
      );

  @override
  String toString() =>
      'SyncState(${status.name}, pending: $pendingCount, '
      'dead: $deadLetteredCount)';
}
