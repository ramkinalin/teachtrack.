// hive_ce_flutter re-exports the whole hive_ce API, so importing both is
// redundant.
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../shared/models/pending_operation.dart';
import '../constants/hive_boxes.dart';

/// Owns Hive initialisation and box lifetimes.
///
/// Boxes are opened once at startup and held for the life of the process, so
/// every read after boot is synchronous and in-memory. That is what makes
/// "local first, never wait" achievable in the UI.
class LocalStorageService {
  LocalStorageService();

  bool _initialised = false;

  // Nullable rather than `late final` so that init/close/init (used by tests and
  // by a future sign-out that clears local data) does not throw.
  Box<PendingOperation>? _pendingOperations;
  Box<dynamic>? _settings;
  Box<dynamic>? _syncMeta;

  Box<PendingOperation> get pendingOperationsBox =>
      _requireBox(_pendingOperations);

  Box<dynamic> get settingsBox => _requireBox(_settings);

  Box<dynamic> get syncMetaBox => _requireBox(_syncMeta);

  /// Must be awaited before `runApp`.
  ///
  /// [subDir] is only used by tests, which call `Hive.init` with a temp path
  /// instead of `initFlutter`.
  Future<void> init({bool useFlutterPath = true, String? subDir}) async {
    if (_initialised) return;

    if (useFlutterPath) {
      await Hive.initFlutter(subDir);
    }

    _registerAdapters();

    _pendingOperations =
        await Hive.openBox<PendingOperation>(HiveBoxes.pendingOperations);
    _settings = await Hive.openBox<dynamic>(HiveBoxes.settings);
    _syncMeta = await Hive.openBox<dynamic>(HiveBoxes.syncMeta);

    _initialised = true;
  }

  void _registerAdapters() {
    if (!Hive.isAdapterRegistered(HiveTypeIds.syncOperationType)) {
      Hive.registerAdapter(SyncOperationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.pendingOperation)) {
      Hive.registerAdapter(PendingOperationAdapter());
    }
  }

  DateTime? get lastSuccessfulSyncAt {
    final Object? raw = syncMetaBox.get(SyncMetaKeys.lastSuccessfulSyncAt);
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  Future<void> setLastSuccessfulSyncAt(DateTime value) =>
      syncMetaBox.put(SyncMetaKeys.lastSuccessfulSyncAt, value.toIso8601String());

  Future<void> close() async {
    if (!_initialised) return;
    await Hive.close();
    _pendingOperations = null;
    _settings = null;
    _syncMeta = null;
    _initialised = false;
  }

  Box<T> _requireBox<T>(Box<T>? box) {
    if (box == null) {
      throw StateError(
        'LocalStorageService.init() must be awaited before accessing boxes.',
      );
    }
    return box;
  }
}
