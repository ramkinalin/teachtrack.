import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';

/// Gets a backup file out of the app and back in.
///
/// Every platform call in the backup feature lives here, so a package API change
/// is one file to fix rather than a hunt. The interface also lets the settings
/// screen be reasoned about without a device.
abstract interface class BackupFileService {
  /// Writes [json] to a temporary file called [fileName] and hands it to the
  /// system share sheet, so the teacher can put it in Drive, email it to
  /// themselves, or send it to another phone.
  Future<Result<void>> share({
    required String json,
    required String fileName,
  });

  /// Asks the teacher to pick a backup file. `null` means they cancelled, which
  /// is not a failure.
  Future<Result<String?>> pickJson();
}

class BackupFileServiceImpl implements BackupFileService {
  const BackupFileServiceImpl();

  @override
  Future<Result<void>> share({
    required String json,
    required String fileName,
  }) async {
    try {
      // The app's own temporary directory: no storage permission needed, and
      // Android clears it by itself. The share sheet copies the file wherever the
      // teacher chooses, so nothing needs to persist here.
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/$fileName');
      await file.writeAsString(json, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/json')],
          subject: 'TeachTrack backup',
          text: 'TeachTrack backup — keep this file safe to restore later.',
        ),
      );

      return okVoid;
    } on Object catch (error) {
      return Err<void>(
        UnexpectedFailure('Could not share the backup', cause: error),
      );
    }
  }

  @override
  Future<Result<String?>> pickJson() async {
    try {
      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[
          // Both offered: some Android file providers report a .json file with a
          // generic mime type, and filtering on only one hides the file the
          // teacher is looking for.
          const XTypeGroup(
            label: 'TeachTrack backup',
            extensions: <String>['json'],
            mimeTypes: <String>['application/json'],
          ),
        ],
      );

      if (file == null) return const Ok<String?>(null);

      return Ok<String?>(await file.readAsString());
    } on Object catch (error) {
      return Err<String?>(
        UnexpectedFailure('Could not read that file', cause: error),
      );
    }
  }
}

/// Test double: records what was shared and returns canned content.
class FakeBackupFileService implements BackupFileService {
  FakeBackupFileService({this.pickedJson});

  /// What [pickJson] returns. `null` mimics the teacher cancelling.
  String? pickedJson;

  String? sharedJson;
  String? sharedFileName;

  @override
  Future<Result<void>> share({
    required String json,
    required String fileName,
  }) async {
    sharedJson = json;
    sharedFileName = fileName;
    return okVoid;
  }

  @override
  Future<Result<String?>> pickJson() async => Ok<String?>(pickedJson);
}
