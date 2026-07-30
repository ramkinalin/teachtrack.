import 'package:hive_ce/hive.dart';

import '../../core/constants/hive_boxes.dart';

/// The kind of mutation a queued operation represents.
enum SyncOperationType { create, update, delete }

/// A single locally-committed write that still needs to reach Firestore.
///
/// This is the heart of the offline-first contract: the UI mutates local state
/// and appends one of these to the outbox, then returns immediately. Nothing in
/// the write path ever awaits the network.
class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.attemptCount = 0,
    this.nextAttemptAt,
    this.lastError,
    this.isDeadLettered = false,
  });

  /// Queue-local identifier (also the Hive key).
  final String id;

  /// Routing key — see `SyncEntityTypes`.
  final String entityType;

  /// Identifier of the domain entity being mutated. Generated client-side so
  /// that records created offline keep a stable id after sync.
  final String entityId;

  final SyncOperationType operation;

  /// JSON-safe representation of the mutation.
  final Map<String, dynamic> payload;

  final DateTime createdAt;

  final int attemptCount;

  /// Earliest time this operation should be retried. `null` means "now".
  final DateTime? nextAttemptAt;

  final String? lastError;

  /// Set once [AppConstants.syncMaxAttempts] is exhausted. Dead-lettered
  /// operations stop consuming Firestore quota and are surfaced to the user
  /// instead of being retried forever.
  final bool isDeadLettered;

  bool isDue(DateTime now) =>
      !isDeadLettered &&
      (nextAttemptAt == null || !nextAttemptAt!.isAfter(now));

  PendingOperation copyWith({
    Map<String, dynamic>? payload,
    SyncOperationType? operation,
    int? attemptCount,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    String? lastError,
    bool clearLastError = false,
    bool? isDeadLettered,
  }) {
    return PendingOperation(
      id: id,
      entityType: entityType,
      entityId: entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt:
          clearNextAttemptAt ? null : (nextAttemptAt ?? this.nextAttemptAt),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      isDeadLettered: isDeadLettered ?? this.isDeadLettered,
    );
  }

  @override
  String toString() =>
      'PendingOperation($entityType/$entityId, ${operation.name}, '
      'attempts: $attemptCount, dead: $isDeadLettered)';
}

/// Hand-written adapter for [SyncOperationType].
///
/// Adapters are written by hand rather than generated: the models are few, and
/// avoiding `build_runner` keeps the build fast and removes a whole class of
/// codegen version conflicts.
class SyncOperationTypeAdapter extends TypeAdapter<SyncOperationType> {
  @override
  final int typeId = HiveTypeIds.syncOperationType;

  @override
  SyncOperationType read(BinaryReader reader) {
    final int index = reader.readByte();
    // Defensive: an unknown index means data written by a newer build.
    if (index < 0 || index >= SyncOperationType.values.length) {
      return SyncOperationType.update;
    }
    return SyncOperationType.values[index];
  }

  @override
  void write(BinaryWriter writer, SyncOperationType obj) {
    writer.writeByte(obj.index);
  }
}

class PendingOperationAdapter extends TypeAdapter<PendingOperation> {
  @override
  final int typeId = HiveTypeIds.pendingOperation;

  @override
  PendingOperation read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };

    return PendingOperation(
      id: fields[0] as String,
      entityType: fields[1] as String,
      entityId: fields[2] as String,
      operation: fields[3] as SyncOperationType,
      payload: Map<String, dynamic>.from(fields[4] as Map),
      createdAt: fields[5] as DateTime,
      attemptCount: fields[6] as int? ?? 0,
      nextAttemptAt: fields[7] as DateTime?,
      lastError: fields[8] as String?,
      isDeadLettered: fields[9] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, PendingOperation obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.entityType)
      ..writeByte(2)
      ..write(obj.entityId)
      ..writeByte(3)
      ..write(obj.operation)
      ..writeByte(4)
      ..write(obj.payload)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.attemptCount)
      ..writeByte(7)
      ..write(obj.nextAttemptAt)
      ..writeByte(8)
      ..write(obj.lastError)
      ..writeByte(9)
      ..write(obj.isDeadLettered);
  }
}
