import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_state_views.dart';
import '../features/dashboard/presentation/screens/sync_diagnostics_screen.dart';
import '../features/events/presentation/screens/events_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/profile/presentation/profile_providers.dart';
import '../features/settings/presentation/screens/manage_subjects_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/timetable/presentation/screens/timetable_editor_screen.dart';
import '../features/timetable/presentation/screens/today_screen.dart';
import 'app_routes.dart';

/// Application router.
///
/// The redirect is the only gate: until setup is completed every route resolves
/// to the wizard, and once it is, the wizard is no longer reachable by URL. This
/// keeps the "have they been introduced yet?" decision in one place instead of
/// spread across screen builders.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.todayPath,
    redirect: (BuildContext context, GoRouterState state) {
      // Read the repository, not the provider: the provider refreshes from an
      // async Hive box event, so immediately after finishing setup it would still
      // report "needs setup" and bounce the teacher straight back to the wizard.
      // The box itself is updated synchronously.
      final bool needsSetup =
          !ref.read(profileRepositoryProvider).isOnboardingCompleted;
      final bool goingToSetup = state.matchedLocation == AppRoutes.onboardingPath;

      if (needsSetup && !goingToSetup) return AppRoutes.onboardingPath;
      if (!needsSetup && goingToSetup) return AppRoutes.todayPath;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.onboardingPath,
        name: AppRoutes.onboardingName,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
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
        path: AppRoutes.eventsPath,
        name: AppRoutes.eventsName,
        builder: (BuildContext context, GoRouterState state) =>
            const EventsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsPath,
        name: AppRoutes.settingsName,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'subjects',
            name: AppRoutes.subjectsName,
            builder: (BuildContext context, GoRouterState state) =>
                const ManageSubjectsScreen(),
          ),
        ],
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
