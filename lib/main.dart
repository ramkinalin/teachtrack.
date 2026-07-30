import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/services/local_storage_service.dart';
import 'features/timetable/data/local/subject_store.dart';
import 'features/timetable/data/local/timetable_local_data_source.dart';
import 'features/timetable/data/local/timetable_seed.dart';
import 'features/timetable/presentation/providers/timetable_providers.dart';
import 'shared/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opening boxes is the only thing awaited before the first frame: every
  // subsequent read is synchronous, which is what lets screens render real data
  // immediately instead of showing spinners.
  final LocalStorageService storage = LocalStorageService();
  await storage.init();

  // Each feature owns its own boxes, so `core` never learns about feature models.
  final TimetableLocalDataSource timetableLocal = TimetableLocalDataSource();
  await timetableLocal.init();

  // A bell schedule and a subject list are defaults every school needs. Sample
  // classes are NOT seeded — a new install must reach the real empty state so
  // setup is visible. The demo week is available from Settings instead.
  await TimetableSeed.ensurePeriods(timetableLocal);
  await SubjectStore(settingsBox: storage.settingsBox).seedIfEmpty();

  runApp(
    ProviderScope(
      overrides: <Override>[
        localStorageServiceProvider.overrideWithValue(storage),
        timetableLocalDataSourceProvider.overrideWithValue(timetableLocal),
      ],
      child: const TeachTrackApp(),
    ),
  );
}
