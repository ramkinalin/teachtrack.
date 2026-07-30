import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../shared/providers/sync_providers.dart';
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

    final GoRouter router = ref.watch(routerProvider);

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
