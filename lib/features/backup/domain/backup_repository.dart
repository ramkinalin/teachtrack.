import '../../../core/utils/result.dart';
import 'backup_payload.dart';

/// Reads everything off the device into a file, and puts it back.
abstract interface class BackupRepository {
  /// Gathers everything into a payload.
  BackupPayload snapshot();

  /// The filename to offer, dated so a teacher keeping several can tell them
  /// apart.
  String suggestedFileName();

  /// Applies [payload]. Writes go through the same validation and outbox as any
  /// other edit, so a restore cannot introduce data the app would refuse.
  Future<Result<RestoreSummary>> restore(
    BackupPayload payload, {
    required RestoreMode mode,
  });
}
