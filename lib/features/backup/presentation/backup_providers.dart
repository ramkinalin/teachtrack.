import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/core_providers.dart';
import '../../events/presentation/providers/event_providers.dart';
import '../../timetable/presentation/providers/timetable_providers.dart';
import '../data/backup_file_service.dart';
import '../data/backup_repository_impl.dart';
import '../domain/backup_repository.dart';

final backupFileServiceProvider = Provider<BackupFileService>(
  (ref) => const BackupFileServiceImpl(),
);

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepositoryImpl(
    settingsBox: ref.watch(localStorageServiceProvider).settingsBox,
    subjects: ref.watch(subjectStoreProvider),
    timetableLocal: ref.watch(timetableLocalDataSourceProvider),
    eventLocal: ref.watch(eventLocalDataSourceProvider),
    overrideLocal: ref.watch(overrideLocalDataSourceProvider),
    timetable: ref.watch(timetableRepositoryProvider),
    overrides: ref.watch(overrideRepositoryProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    clock: ref.watch(clockProvider),
  );
});
