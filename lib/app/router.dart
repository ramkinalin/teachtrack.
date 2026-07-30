import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_state_views.dart';
import '../features/dashboard/presentation/screens/sync_diagnostics_screen.dart';
import '../features/timetable/presentation/screens/timetable_editor_screen.dart';
import '../features/timetable/presentation/screens/today_screen.dart';
import 'app_routes.dart';

/// Application router.
///
/// Kept in a provider so that a future auth guard can redirect based on session
/// state without restructuring anything.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.todayPath,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.todayPath,
        name: AppRoutes.todayName,
        builder: (BuildContext context, GoRouterState state) =>
            const TodayScreen(),
      ),
      GoRoute(
        path: AppRoutes.timetablePath,
        name: AppRoutes.timetableName,
        builder: (BuildContext context, GoRouterState state) =>
            const TimetableEditorScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnosticsPath,
        name: AppRoutes.diagnosticsName,
        builder: (BuildContext context, GoRouterState state) =>
            const SyncDiagnosticsScreen(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: AppErrorView(
        message: 'Screen not found: ${state.uri}',
        onRetry: () => context.goNamed(AppRoutes.todayName),
      ),
    ),
  );
});
