import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/events/presentation/providers/event_providers.dart';
import '../shared/providers/sync_providers.dart';
import 'app_routes.dart';
import 'router.dart';

/// Root widget.
///
/// Watching [syncStateProvider] here is what keeps the sync engine alive for the
/// whole session; the provider itself never blocks the first frame.
class TeachTrackApp extends ConsumerWidget {
  const TeachTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncStateProvider);
    // Keeps pending reminders in step with stored events for the whole session.
    ref.watch(eventRemindersProvider);

    final GoRouter router = ref.watch(routerProvider);

    // Tapping a reminder should land on the events list rather than wherever the
    // app happened to be left.
    ref.listen<AsyncValue<String>>(
      tappedReminderEventIdProvider,
      (AsyncValue<String>? previous, AsyncValue<String> next) {
        next.whenData((String _) => router.goNamed(AppRoutes.eventsName));
      },
    );

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
