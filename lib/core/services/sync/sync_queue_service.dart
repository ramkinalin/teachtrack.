import 'dart:async';
import 'dart:math' as math;

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/pending_operation.dart';
import '../../constants/app_constants.dart';
import '../../utils/clock.dart';

/// Durable outbox for local writes awaiting synchronisation.
///
/// Two properties matter most:
///   * Appending is a single local Hive write, so callers never block.
///   * Repeated edits to the same entity are *coalesced* rather than stacked,
///     which directly reduces Firestore writes on the Spark plan — a teacher
///     toggling a class status five times still costs one remote write.
class SyncQueueService {
  SyncQueueService({
    required Box<PendingOperation> box,
    Clock clock = const Clock(),
    Uuid? uuid,
  })  : _box = box,
        _clock = clock,
        _uuid = uuid ?? const Uuid();

  final Box<PendingOperation> _box;
  final Clock _clock;
  final Uuid _uuid;

  /// Ids currently being pushed upstream.
  ///
  /// A remote batch can take hundreds of milliseconds, and the UI keeps writing
  /// throughout. Coalescing into an operation that is already in flight would
  /// lose the newer edit, because the engine deletes the id on success. While an
  /// id is in flight it is invisible to both coalescing and dispatch, so a
  /// concurrent write becomes a *new* queue entry instead.
  final Set<String> _inFlight = <String>{};

  int get pendingCount =>
      _box.values.where((PendingOperation op) => !op.isDeadLettered).length;

  int get deadLetteredCount =>
      _box.values.where((PendingOperation op) => op.isDeadLettered).length;

  /// Fires whenever the queue changes; used to drive UI badges.
  Stream<void> watchChanges() => _box.watch().map((BoxEvent _) {});

  /// Appends (or coalesces into) an operation for [entityType]/[entityId].
  ///
  /// Coalescing rules, applied against the newest live operation for the same
  /// entity:
  ///   * pending `create` + `update`  -> `create` with merged payload
  ///   * pending `update` + `update`  -> `update` with merged payload
  ///   * pending `create` + `delete`  -> operation dropped entirely (the record
  ///     never reached the server, so there is nothing to delete remotely)
  ///   * anything    + `delete`       -> `delete`
  ///   * pending `delete` + `create`/`update` -> the new operation replaces the
  ///     delete outright; merging payloads here would resurrect fields from the
  ///     record that was just removed
  ///
  /// A retry back-off already in progress is preserved so that a failing entity
  /// cannot be pushed back to the front of the queue by further local edits.
  Future<PendingOperation?> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperationType operation,
    required Map<String, dynamic> payload,
  }) async {
    final PendingOperation? existing = _liveOperationFor(entityType, entityId);

    if (existing == null) {
      final PendingOperation op = PendingOperation(
        id: _uuid.v4(),
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payload: Map<String, dynamic>.unmodifiable(payload),
        createdAt: _clock.now(),
      );
      await _box.put(op.id, op);
      return op;
    }

    if (operation == SyncOperationType.delete) {
      if (existing.operation == SyncOperationType.create) {
        await _box.delete(existing.id);
        return null;
      }
      final PendingOperation deleted = existing.copyWith(
        operation: SyncOperationType.delete,
        payload: Map<String, dynamic>.unmodifiable(payload),
      );
      await _box.put(deleted.id, deleted);
      return deleted;
    }

    // Re-creating or editing an entity whose delete is still queued: the new
    // operation wins wholesale, and payloads are NOT merged.
    if (existing.operation == SyncOperationType.delete) {
      final PendingOperation replaced = existing.copyWith(
        operation: operation,
        payload: Map<String, dynamic>.unmodifiable(payload),
      );
      await _box.put(replaced.id, replaced);
      return replaced;
    }

    // create/update collapse into the existing operation type.
    final PendingOperation merged = existing.copyWith(
      payload: Map<String, dynamic>.unmodifiable(<String, dynamic>{
        ...existing.payload,
        ...payload,
      }),
    );
    await _box.put(merged.id, merged);
    return merged;
  }

  /// Marks operations as being pushed upstream. Cleared by [markSucceeded] or
  /// [markFailed].
  void markDispatching(Iterable<PendingOperation> operations) {
    _inFlight.addAll(operations.map((PendingOperation op) => op.id));
  }

  /// Operations eligible for dispatch right now, oldest first.
  List<PendingOperation> dueOperations({
    int limit = AppConstants.syncBatchSize,
  }) {
    final DateTime now = _clock.now();
    final List<PendingOperation> due = _box.values
        .where(
          (PendingOperation op) => op.isDue(now) && !_inFlight.contains(op.id),
        )
        .toList(growable: false)
      ..sort(
        (PendingOperation a, PendingOperation b) =>
            a.createdAt.compareTo(b.createdAt),
      );
    return due.length <= limit ? due : due.sublist(0, limit);
  }

  List<PendingOperation> deadLetteredOperations() => _box.values
      .where((PendingOperation op) => op.isDeadLettered)
      .toList(growable: false);

  /// Earliest future retry time across all live operations, or `null` if none
  /// are waiting on a back-off. Used by the engine to wake itself up.
  DateTime? earliestScheduledAttempt() {
    DateTime? earliest;
    for (final PendingOperation op in _box.values) {
      if (op.isDeadLettered) continue;
      final DateTime? next = op.nextAttemptAt;
      if (next == null) continue;
      if (earliest == null || next.isBefore(earliest)) earliest = next;
    }
    return earliest;
  }

  Future<void> markSucceeded(Iterable<PendingOperation> operations) async {
    final List<String> ids =
        operations.map((PendingOperation op) => op.id).toList(growable: false);
    _inFlight.removeAll(ids);
    await _box.deleteAll(ids);
  }

  /// Records a failure and schedules the next attempt with exponential
  /// back-off, dead-lettering once the attempt budget is spent.
  Future<void> markFailed(
    Iterable<PendingOperation> operations,
    Object error,
  ) async {
    final DateTime now = _clock.now();
    final Map<String, PendingOperation> updates = <String, PendingOperation>{};

    _inFlight.removeAll(operations.map((PendingOperation op) => op.id));

    for (final PendingOperation op in operations) {
      // Skip if the operation was coalesced away or already cleared.
      if (!_box.containsKey(op.id)) continue;

      final int attempts = op.attemptCount + 1;
      final bool exhausted = attempts >= AppConstants.syncMaxAttempts;

      updates[op.id] = op.copyWith(
        attemptCount: attempts,
        lastError: error.toString(),
        isDeadLettered: exhausted,
        nextAttemptAt: exhausted ? null : now.add(backoffFor(attempts)),
        clearNextAttemptAt: exhausted,
      );
    }

    if (updates.isNotEmpty) await _box.putAll(updates);
  }

  /// Clears the dead-letter flag so the user can retry manually.
  Future<void> requeue(PendingOperation operation) => _box.put(
        operation.id,
        operation.copyWith(
          attemptCount: 0,
          isDeadLettered: false,
          clearNextAttemptAt: true,
          clearLastError: true,
        ),
      );

  Future<void> discard(PendingOperation operation) => _box.delete(operation.id);

  /// `base * 2^(attempt-1)`, capped. Attempt numbers are 1-based.
  static Duration backoffFor(int attempt) {
    final int exponent = math.max(0, attempt - 1);
    // Cap the exponent before shifting to avoid integer overflow.
    final int multiplier = 1 << math.min(exponent, 20);
    final int millis =
        AppConstants.syncRetryBaseDelay.inMilliseconds * multiplier;
    return Duration(
      milliseconds: math.min(
        millis,
        AppConstants.syncRetryMaxDelay.inMilliseconds,
      ),
    );
  }

  PendingOperation? _liveOperationFor(String entityType, String entityId) {
    PendingOperation? newest;
    for (final PendingOperation op in _box.values) {
      if (op.isDeadLettered || _inFlight.contains(op.id)) continue;
      if (op.entityType != entityType || op.entityId != entityId) continue;
      if (newest == null || op.createdAt.isAfter(newest.createdAt)) {
        newest = op;
      }
    }
    return newest;
  }
}
