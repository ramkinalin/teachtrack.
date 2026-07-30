import 'dart:async';

import '../../../shared/models/pending_operation.dart';
import '../../../shared/models/sync_state.dart';
import '../../constants/app_constants.dart';
import '../../utils/clock.dart';
import '../connectivity_service.dart';
import '../local_storage_service.dart';
import 'remote_sync_handler.dart';
import 'sync_queue_service.dart';

/// Background drainer for the outbox.
///
/// Runs entirely off the UI path: nothing in the widget tree ever awaits it.
/// Triggers are (a) regaining connectivity, (b) a new local write, (c) a
/// scheduled retry, (d) a periodic safety sweep. Batches are grouped by entity
/// type so each handler can issue one Firestore batch per pass.
class SyncEngine {
  SyncEngine({
    required SyncQueueService queue,
    required ConnectivityService connectivity,
    required LocalStorageService storage,
    Clock clock = const Clock(),
    Duration interval = AppConstants.syncInterval,
  })  : _queue = queue,
        _connectivity = connectivity,
        _storage = storage,
        _clock = clock,
        _interval = interval;

  final SyncQueueService _queue;
  final ConnectivityService _connectivity;
  final LocalStorageService _storage;
  final Clock _clock;
  final Duration _interval;

  final Map<String, RemoteSyncHandler> _handlers =
      <String, RemoteSyncHandler>{};
  final StreamController<SyncState> _states =
      StreamController<SyncState>.broadcast();

  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<void>? _queueSub;
  Timer? _periodicTimer;
  Timer? _retryTimer;

  bool _draining = false;
  bool _started = false;
  Future<void>? _inFlightDrain;
  SyncState _state = const SyncState();

  SyncState get state => _state;

  /// Broadcast stream of state snapshots. Replays the current value on listen.
  Stream<SyncState> get states async* {
    yield _state;
    yield* _states.stream;
  }

  /// Registers a feature's remote handler. Idempotent per entity type.
  void registerHandler(RemoteSyncHandler handler) {
    _handlers[handler.entityType] = handler;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _connectivitySub = _connectivity.onStatusChanged.listen((bool online) {
      _refreshCounts();
      if (online) {
        unawaited(drain());
      } else {
        _emit(_state.copyWith(status: SyncStatus.offline));
      }
    });

    // A new local write should sync promptly when a connection is available.
    // Hive delivers box events asynchronously, so events caused by the engine's
    // own bookkeeping arrive after a pass has finished — hence `force: false`,
    // which leaves an already-armed back-off timer alone instead of pulling a
    // scheduled retry forward to 500ms.
    _queueSub = _queue.watchChanges().listen((void _) {
      _refreshCounts();
      if (_connectivity.isOnline && !_draining) {
        _scheduleRetry(const Duration(milliseconds: 500));
      }
    });

    _periodicTimer = Timer.periodic(_interval, (Timer _) => unawaited(drain()));

    _emit(
      _state.copyWith(
        pendingCount: _queue.pendingCount,
        deadLetteredCount: _queue.deadLetteredCount,
        lastSuccessfulSyncAt: _storage.lastSuccessfulSyncAt,
      ),
    );

    await _connectivity.checkNow();
    await drain();
  }

  /// Attempts one drain pass.
  ///
  /// Safe to call concurrently: overlapping calls join the pass already in
  /// flight rather than starting a second one, so `await drain()` always means
  /// "a pass has completed".
  Future<void> drain() {
    final Future<void>? inFlight = _inFlightDrain;
    if (inFlight != null) return inFlight;

    final Future<void> pass = _drain();
    _inFlightDrain = pass;
    return pass.whenComplete(() => _inFlightDrain = null);
  }

  Future<void> _drain() async {
    if (!_started) return;

    if (!_connectivity.isOnline) {
      _emit(_state.copyWith(status: SyncStatus.offline));
      return;
    }

    final List<PendingOperation> due = _queue.dueOperations();
    if (due.isEmpty) {
      // Queued-but-not-yet-due work is "retrying", not "synced" — and the last
      // error stays visible until something actually succeeds.
      final bool hasWaitingWork = _queue.pendingCount > 0;
      _emit(
        _state.copyWith(
          status: hasWaitingWork ? SyncStatus.retrying : _idleStatus(),
          pendingCount: _queue.pendingCount,
          deadLetteredCount: _queue.deadLetteredCount,
          clearLastError: !hasWaitingWork,
        ),
      );
      _scheduleNextRetryFromQueue();
      return;
    }

    _draining = true;
    _emit(_state.copyWith(status: SyncStatus.syncing));

    Object? firstError;

    try {
      for (final MapEntry<String, List<PendingOperation>> group
          in _groupByEntityType(due).entries) {
        final RemoteSyncHandler? handler = _handlers[group.key];

        if (handler == null) {
          final Object error = StateError(
            'No RemoteSyncHandler registered for "${group.key}"',
          );
          firstError ??= error;
          await _queue.markFailed(group.value, error);
          continue;
        }

        // Hide the batch from coalescing and re-dispatch for the duration of
        // the remote call, so a concurrent local edit becomes a new queue entry
        // instead of being deleted along with the batch on success.
        _queue.markDispatching(group.value);

        try {
          await handler.applyBatch(group.value);
          await _queue.markSucceeded(group.value);
        } on Object catch (error) {
          firstError ??= error;
          await _queue.markFailed(group.value, error);
        }
      }
    } finally {
      _draining = false;
    }

    if (firstError == null) {
      final DateTime now = _clock.now();
      await _storage.setLastSuccessfulSyncAt(now);
      _emit(
        _state.copyWith(
          status: _idleStatus(),
          pendingCount: _queue.pendingCount,
          deadLetteredCount: _queue.deadLetteredCount,
          lastSuccessfulSyncAt: now,
          clearLastError: true,
        ),
      );
    } else {
      _emit(
        _state.copyWith(
          status: _queue.deadLetteredCount > 0
              ? SyncStatus.needsAttention
              : SyncStatus.retrying,
          pendingCount: _queue.pendingCount,
          deadLetteredCount: _queue.deadLetteredCount,
          lastError: firstError.toString(),
        ),
      );
    }

    _scheduleNextRetryFromQueue();
  }

  /// Retries a dead-lettered operation on explicit user request.
  Future<void> retryDeadLettered(PendingOperation operation) async {
    await _queue.requeue(operation);
    await drain();
  }

  SyncStatus _idleStatus() => _queue.deadLetteredCount > 0
      ? SyncStatus.needsAttention
      : SyncStatus.synced;

  void _refreshCounts() {
    _emit(
      _state.copyWith(
        pendingCount: _queue.pendingCount,
        deadLetteredCount: _queue.deadLetteredCount,
      ),
    );
  }

  /// Wakes the engine when the earliest scheduled retry becomes due, so short
  /// back-offs are not delayed by the long periodic interval.
  void _scheduleNextRetryFromQueue() {
    final DateTime? earliest = _queue.earliestScheduledAttempt();
    if (earliest == null) return;

    final Duration delay = earliest.difference(_clock.now());
    _scheduleRetry(delay.isNegative ? Duration.zero : delay, force: true);
  }

  /// Arms the wake-up timer. Unless [force] is set, an already-armed timer wins:
  /// an incidental trigger must not shorten a computed back-off.
  void _scheduleRetry(Duration delay, {bool force = false}) {
    if (!force && (_retryTimer?.isActive ?? false)) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(drain()));
  }

  static Map<String, List<PendingOperation>> _groupByEntityType(
    List<PendingOperation> operations,
  ) {
    final Map<String, List<PendingOperation>> grouped =
        <String, List<PendingOperation>>{};
    for (final PendingOperation op in operations) {
      grouped.putIfAbsent(op.entityType, () => <PendingOperation>[]).add(op);
    }
    return grouped;
  }

  void _emit(SyncState next) {
    if (next == _state) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    _started = false;
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    await _connectivitySub?.cancel();
    await _queueSub?.cancel();
    await _states.close();
  }
}
